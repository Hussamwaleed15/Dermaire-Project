import asyncio
from io import BytesIO
import threading
from unittest.mock import Mock

import pytest
from fastapi import UploadFile
from starlette.datastructures import Headers
from PIL import Image, PngImagePlugin

from app.api.v1 import checkins
from app.models import User
from test_capture_quality import context, photograph


ANALYSIS = {
    'azure_vision_status': 'ANALYSIS_COMPLETE',
    'estimated_hydration_score': 60,
    'surface_texture_score': 70,
    'erythema_redness_score': 20,
}


def submit(db, data, media_type):
    return checkins.submit_daily_checkin(
        time_of_day='Morning', hydration_score=None, texture_score=None,
        redness_score=None, notes=None, experiment_id=None, report=None,
        idempotency_key='vision-boundary',
        photo=UploadFile(BytesIO(data), filename='private-photo',
                         headers=Headers({'content-type': media_type})),
        current_user=db.get(User, 'capture-user-0'), db=db,
    )


@pytest.mark.parametrize('format,media_type', [('JPEG', 'image/jpeg'), ('PNG', 'image/png')])
def test_vision_receives_sanitized_bytes(context, photograph, monkeypatch, format, media_type):
    _, db, _ = context
    exif = Image.Exif()
    exif[270] = 'private-location'
    exif[274] = 1
    stream = BytesIO()
    options = {'exif': exif}
    if format == 'PNG':
        text = PngImagePlugin.PngInfo()
        text.add_text('Comment', 'private-location')
        options['pnginfo'] = text
    photograph.save(stream, format=format, **options)
    original = stream.getvalue()
    with Image.open(BytesIO(original)) as uploaded:
        assert uploaded.getexif()[270] == 'private-location'
    analyze = Mock(return_value=dict(ANALYSIS))
    store = Mock()
    monkeypatch.setattr(checkins.azure_vision_service, 'analyze_skin_image', analyze)
    monkeypatch.setattr(checkins.azure_blob_service, 'upload_capture', store)

    result = asyncio.run(submit(db, original, media_type))

    assert result.storage == 'azure_blob'
    analyze.assert_called_once()
    sanitized = analyze.call_args.args[0]
    assert sanitized != original
    assert sanitized == store.call_args.args[1]
    with Image.open(BytesIO(sanitized)) as image:
        assert image.format == 'PNG'
        assert image.size == photograph.size
        assert not image.getexif()
        assert 'private-location' not in str(image.info)
        assert 'Comment' not in image.info


def test_vision_runs_in_worker_without_blocking_event_loop(context, photograph, monkeypatch):
    _, db, _ = context
    stream = BytesIO()
    photograph.save(stream, format='PNG')
    monkeypatch.setattr(checkins.azure_blob_service, 'upload_capture', Mock())

    async def exercise():
        loop = asyncio.get_running_loop()
        handler_thread = threading.get_ident()
        event_loop_responded = threading.Event()
        observed = {}

        def analyze(data):
            observed['thread'] = threading.get_ident()
            # This callback can run only if the async handler releases the loop.
            loop.call_soon_threadsafe(event_loop_responded.set)
            observed['responsive'] = event_loop_responded.wait(timeout=3)
            return dict(ANALYSIS)

        monkeypatch.setattr(checkins.azure_vision_service, 'analyze_skin_image', analyze)
        result = await submit(db, stream.getvalue(), 'image/png')
        assert result.storage == 'azure_blob'
        assert observed['thread'] != handler_thread
        assert observed['responsive'], 'Vision blocked the request event loop'

    asyncio.run(exercise())
