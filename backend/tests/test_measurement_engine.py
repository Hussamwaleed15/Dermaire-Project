from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock
import sqlite3
import numpy as np
import pytest
from PIL import Image
from app.models import Capture, Measurement
from app.services import measurement as engine, capture_quality as gate
from app.services.azure_blob import azure_blob_service
from test_capture_quality import context, photograph, encoded, upload


def accepted(client, headers, image):
    res = upload(client, headers, encoded(image))
    assert res.status_code == 201, res.text
    assert res.json()['state'] == 'accepted'
    return res.json()


def test_inline_provenance_idempotency(context, photograph):
    client, db, headers = context
    capture = accepted(client,headers[0],photograph); row = capture['measurement']
    assert capture['storage'] == 'not_persisted' and row['status'] == 'measured'
    assert set(row['metrics']) == set(engine.SPECS)
    assert row['capture_quality'] == capture['quality'] and row['capture_id'] == capture['id']
    for key, m in row['metrics'].items():
        assert 0 <= m['value'] <= 1 and m['unit'] == 'fraction_0_to_1'
        assert m['key'] == key and m['method_version'] == row['algorithm_version'] == engine.VERSION
        assert m['source_capture_id'] == capture['id'] and m['measured_at'].endswith('+00:00')
        assert m['limitations'] and m['reliability'] == 'limited_image_proxy'
    assert 'hydration' not in str(row)
    for method in (client.get,client.post):
        assert method('/api/v1/measurements/'+capture['id'],headers=headers[0]).json() == row
    assert db.query(Measurement).count() == 1


def test_previous_unknown_history(context, photograph):
    client,db,headers=context
    a=accepted(client,headers[0],photograph); b=accepted(client,headers[0],photograph)
    cmp=b['measurement']['comparison']
    assert cmp['previous_measurement_id'] == a['measurement']['id']
    assert cmp['state']=='not_comparable' and cmp['reason']=='unknown_or_failed_yaw'
    assert cmp['deltas'] is None and cmp['previous_comparable_measurement_id'] is None
    assert [r['capture_id'] for r in client.get('/api/v1/measurements',headers=headers[0]).json()] == [b['id'],a['id']]
    assert len(client.get('/api/v1/measurements?limit=1',headers=headers[0]).json())==1
    for limit in ('101','zero','0'):
        assert client.get('/api/v1/measurements?limit='+limit,headers=headers[0]).status_code==422


def test_ownership_rejected_auth(context,photograph):
    client,db,headers=context; a=accepted(client,headers[0],photograph)
    rejected=upload(client,headers[0],encoded(Image.new('RGB',(100,100)))).json()
    assert 'measurement' not in rejected
    for method in (client.get,client.post):
        for ref, auth, status in [(a['id'],headers[1],404),('missing',headers[0],404),(rejected['id'],headers[0],409),(a['id'],{},401)]:
            assert method('/api/v1/measurements/'+ref,headers=auth).status_code==status
    assert client.get('/api/v1/measurements',headers=headers[1]).json()==[]
    assert client.get('/api/v1/measurements').status_code==401
    assert db.query(Measurement).count()==1


def historical(db,quality,when=None):
    c=Capture(user_id='capture-user-0',state='accepted',source='upload',view='front',quality=quality,
              storage='not_persisted',server_version='test',received_at=when or datetime.now(timezone.utc))
    db.add(c);db.commit();return c


def test_historical_invalid_payload(context,photograph):
    client,db,headers=context; c=historical(db,gate.assess(photograph,1)); path='/api/v1/measurements/'+c.id
    assert client.get(path,headers=headers[0]).status_code==404
    assert client.post(path,headers=headers[0],json={'value':.7}).status_code==422
    assert db.query(Measurement).count()==0
    row=client.post(path,headers=headers[0]).json()
    assert row['status']=='unavailable' and all(m['value'] is None for m in row['metrics'].values())
    assert client.post(path,headers=headers[0]).json()==row


@pytest.mark.parametrize('data,mime,status',[(b'bad','image/png',422),(b'GIF','image/gif',415)])
def test_invalid_input(context,data,mime,status):
    client,db,headers=context
    assert upload(client,headers[0],data,mime).status_code==status
    assert db.query(Capture).count()==db.query(Measurement).count()==0


def test_compute_failure(context,photograph,monkeypatch):
    client,db,headers=context
    monkeypatch.setattr(engine,'compute',Mock(side_effect=RuntimeError('offline')))
    row=accepted(client,headers[0],photograph)['measurement']
    assert row['status']=='failed' and all(m['value'] is None for m in row['metrics'].values())


@pytest.mark.parametrize('mode',['upload','historical'])
def test_rollback(context,photograph,monkeypatch,mode):
    client,db,headers=context
    c=historical(db,gate.assess(photograph,1)) if mode=='historical' else None
    monkeypatch.setattr(db,'commit',Mock(side_effect=RuntimeError('offline')))
    res=client.post('/api/v1/measurements/'+c.id,headers=headers[0]) if c else upload(client,headers[0],encoded(photograph))
    assert res.status_code==503 and db.query(Measurement).count()==0
    assert db.query(Capture).count()==(1 if c else 0)


def test_deletion_session(context,photograph,monkeypatch):
    client,db,headers=context; c=accepted(client,headers[0],photograph)
    monkeypatch.setattr(azure_blob_service,'delete_owned_images',Mock())
    assert client.delete('/api/v1/users/me',headers=headers[0]).status_code==204
    assert db.query(Measurement).count()==db.query(Capture).count()==0
    assert client.get('/api/v1/measurements/'+c['id'],headers=headers[0]).status_code==401


def complete_quality():
    # Hypothetical verified gate: test only, never accepted from API clients.
    checks={k:{'status':'pass','metrics':{}} for k in ('yaw','pitch','occlusion','uneven_lighting')}
    for key,metrics in {'scale':{'face_width_fraction':.5},'roll':{'degrees':0},
                        'exposure':{'dark_clipped_fraction':0,'bright_clipped_fraction':0},
                        'framing':{'center_offset_x':0,'center_offset_y':0},'sharpness':{'laplacian_variance':100}}.items():
        checks[key]={'status':'pass','metrics':metrics}
    return {'version':'hypothetical-verified-gate','decision':'accepted','checks':checks}


def record(values=None):
    return Measurement(id='test',user_id='self',capture_id='capture',algorithm_version=engine.VERSION,status='measured',
                       results={k:{'value':(values or {}).get(k,.1),'status':'measured','method_version':engine.VERSION,'unit':engine.SPECS[k][0]} for k in engine.SPECS},quality_reference=complete_quality())


def test_no_meaningful_change():
    cmp=engine.compare(record(),record())
    assert cmp['state']=='comparable' and all(d['change']=='no_meaningful_change' for d in cmp['deltas'].values())


@pytest.mark.parametrize('key,metric,value',[('scale','face_width_fraction',.7),('roll','degrees',8),('exposure','bright_clipped_fraction',.1),('framing','center_offset_x',.1)])
def test_mismatch(key,metric,value):
    a,b=record(),record();a.quality_reference['checks'][key]['metrics'][metric]=value
    cmp=engine.compare(a,b)
    assert cmp['reason']=='mismatch_'+key and cmp['deltas'] is None


@pytest.mark.parametrize('key',['yaw','pitch','occlusion','uneven_lighting'])
def test_unknown(key):
    a,b=record(),record();a.quality_reference['checks'][key]['status']='unknown'
    assert engine.compare(a,b)['reason']=='unknown_or_failed_'+key


def test_version_owner_missing_quality():
    a,b=record(),record();b.user_id='other'
    assert engine.compare(a,b)['reason']=='owner_or_algorithm_mismatch'
    b.user_id='self';b.algorithm_version='old'
    assert engine.compare(a,b)['deltas'] is None
    b.algorithm_version=engine.VERSION;b.quality_reference['version']='old'
    assert engine.compare(a,b)['reason']=='quality_version_or_acceptance_mismatch'
    b.quality_reference=complete_quality();b.quality_reference['checks'].pop('scale')
    assert engine.compare(a,b)['reason']=='unknown_scale'


def test_synthetic_direction_brightness(monkeypatch):
    monkeypatch.setattr(gate,'detect_geometry',lambda _: ([(160,200,320,320)],[]))
    q={'decision':'accepted'}
    status,low,_=engine.compute(Image.new('RGB',(800,1000),(120,100,100)),q)
    _,high,_=engine.compute(Image.new('RGB',(800,1000),(160,100,100)),q)
    _,dim,_=engine.compute(Image.new('RGB',(800,1000),(60,50,50)),q)
    assert status=='measured' and low['red_chromaticity_proxy']==dim['red_chromaticity_proxy']
    delta=engine.compare(record(high),record(low))['deltas']['red_chromaticity_proxy']
    assert delta['value']>0 and delta['change']=='increase'
    base=np.full((1000,800,3),120,dtype=np.uint8);noisy=base.copy();noisy[::4,:,:]=150
    _,smooth,_=engine.compute(Image.fromarray(base),q);_,texture,_=engine.compute(Image.fromarray(noisy),q)
    assert texture['texture_contrast_proxy']>smooth['texture_contrast_proxy']==0


@pytest.mark.parametrize('kind',['no_face','small','dark','bright'])
def test_insufficient(kind,monkeypatch):
    faces=[] if kind=='no_face' else [(160,200,40,40)] if kind=='small' else [(160,200,320,320)]
    monkeypatch.setattr(gate,'detect_geometry',lambda _: (faces,[]))
    color=0 if kind=='dark' else 255 if kind=='bright' else 120
    status,values,reason=engine.compute(Image.new('RGB',(800,1000),(color,)*3),{'decision':'accepted'})
    assert status=='insufficient_quality' and values=={} and reason


def test_algorithm_version(context,photograph,monkeypatch):
    client,db,headers=context;c=accepted(client,headers[0],photograph)
    monkeypatch.setattr(engine,'VERSION','measurement-test-next')
    path='/api/v1/measurements/'+c['id'];row=client.post(path,headers=headers[0]).json()
    assert row['status']=='unavailable' and row['algorithm_version']=='measurement-test-next'
    assert db.query(Measurement).count()==2 and client.post(path,headers=headers[0]).json()['id']==row['id']


def test_old_capture_no_future_reference(context,photograph):
    client,db,headers=context;c=historical(db,gate.assess(photograph,1),datetime.now(timezone.utc)-timedelta(days=1))
    accepted(client,headers[0],photograph)
    row=client.post('/api/v1/measurements/'+c.id,headers=headers[0]).json()
    assert row['comparison']['previous_measurement_id'] is None


def test_migration():
    db=sqlite3.connect(':memory:');db.execute('PRAGMA foreign_keys=ON')
    for table in ('users','captures'):db.execute(f'CREATE TABLE {table}(id VARCHAR(36) PRIMARY KEY)')
    db.executescript((Path(__file__).parents[2]/'docs/migrations/measurement-engine-v1-sqlite.sql').read_text())
    assert set(r[1] for r in db.execute('PRAGMA table_info(measurements)'))==set(Measurement.__table__.columns.keys())
    sql="INSERT INTO measurements VALUES(?, ?, ?, ?, ?, '2026-10-02', '{}', '{}', '{}')"
    with pytest.raises(sqlite3.IntegrityError):db.execute(sql,('m','u','c',engine.VERSION,'measured'))
    db.execute("INSERT INTO users VALUES('u')");db.execute("INSERT INTO captures VALUES('c')")
    with pytest.raises(sqlite3.IntegrityError):db.execute(sql,('bad','u','c',engine.VERSION,'fake'))
    db.execute(sql,('m','u','c',engine.VERSION,'measured'))
    with pytest.raises(sqlite3.IntegrityError):db.execute(sql,('duplicate','u','c',engine.VERSION,'measured'))
    db.execute(sql,('next','u','c','next','unavailable'))
    with pytest.raises(sqlite3.IntegrityError):db.execute("DELETE FROM captures WHERE id='c'")
    db.close()

def test_service_rejected_guard(context):
    _,db,_=context
    c=Capture(id='rejected',user_id='capture-user-0',state='rejected')
    with pytest.raises(ValueError,match='accepted'):engine.build(db,c)
    assert db.query(Measurement).count()==0


def test_invalid_metric_provenance_and_sharpness():
    a,b=record(),record();b.results['red_chromaticity_proxy']['value']=float('nan')
    assert engine.compare(a,b)['reason']=='invalid_metric_provenance'
    b=record();b.quality_reference['checks']['sharpness']['metrics']['laplacian_variance']=200
    assert engine.compare(a,b)['reason']=='mismatch_sharpness'


def test_find_prior_comparable_not_nearest_mismatch(context,photograph,monkeypatch):
    _,db,_=context
    monkeypatch.setattr(engine,'compute',lambda *_: ('measured',{key:.2 for key in engine.SPECS},None))
    now=datetime.now(timezone.utc)
    first=historical(db,complete_quality(),now-timedelta(days=3))
    a=engine.build(db,first,photograph);db.commit()
    mismatch=complete_quality();mismatch['checks']['scale']['metrics']['face_width_fraction']=.7
    second=historical(db,mismatch,now-timedelta(days=2));engine.build(db,second,photograph);db.commit()
    last=historical(db,complete_quality(),now)
    row=engine.build(db,last,photograph)
    assert row.comparison['previous_comparable_measurement_id']==a.id
    assert row.comparison['state']=='comparable'


def test_api_insufficient_patch(context,photograph,monkeypatch):
    client,db,headers=context
    monkeypatch.setattr(engine,'compute',lambda *_: ('insufficient_quality',{},'cheek_exposure_insufficient'))
    row=accepted(client,headers[0],photograph)['measurement']
    assert row['status']=='insufficient_quality' and all(m['value'] is None for m in row['metrics'].values())


def test_external_delete_failure_preserves_measurements(context,photograph,monkeypatch):
    client,db,headers=context;accepted(client,headers[0],photograph)
    monkeypatch.setattr(azure_blob_service,'delete_owned_images',Mock(side_effect=RuntimeError('offline')))
    assert client.delete('/api/v1/users/me',headers=headers[0]).status_code==503
    assert db.query(Measurement).count()==db.query(Capture).count()==1

def test_session_revoked_by_credential_change(context,photograph):
    from app.models import User
    client,db,headers=context;c=accepted(client,headers[0],photograph)
    db.query(User).filter_by(id='capture-user-0').first().hashed_password='rotated';db.commit()
    for method in (client.get,client.post):
        assert method('/api/v1/measurements/'+c['id'],headers=headers[0]).status_code==401


def test_cross_account_corruption_blocks_deletion(context,photograph,monkeypatch):
    client,db,headers=context;c=accepted(client,headers[0],photograph)
    foreign=Measurement(user_id='capture-user-1',capture_id=c['id'],algorithm_version='bad-import',
                        status='unavailable',results={},quality_reference={},comparison={})
    db.add(foreign);db.commit()
    delete=Mock();monkeypatch.setattr(azure_blob_service,'delete_owned_images',delete)
    assert client.delete('/api/v1/users/me',headers=headers[0]).status_code==503
    delete.assert_not_called()
    assert db.query(Measurement).count()==2
    assert client.get('/api/v1/measurements',headers=headers[1]).json()==[]
