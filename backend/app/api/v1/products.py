from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status, Header, HTTPException, Response, Request
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.exceptions import EntityNotFoundException, DermaireException
from app.api.deps import get_current_user, record_audit
from app.models import User, Product, RoutineEntry, Experiment, ProductIntelligence, AuditLog, ProductCreateAttempt
from app.services.deletion_journal import deletion_journal
from app.services.experiments import guard_routine_write
from app.services.routine import lock_owner, deactivate
from app.services import product_revisions
from sqlalchemy.orm.exc import StaleDataError
from sqlalchemy.exc import IntegrityError
from datetime import datetime, timezone
from app.services import product_attempts
from app.services import product_mutations
from app.services.resource_revisions import header
from app.schemas.product_attempts import ProductCreateAttemptOut
from app.schemas import (
    ProductCreate, ProductUpdate, ProductOut,
    ProductInteractionCheckRequest
)

router = APIRouter(prefix="/products", tags=["Products & Routine Management"])

@router.get("", response_model=List[ProductOut])
def list_products(
    category: Optional[str] = None,
    status_filter: Optional[str] = Query(None, alias="status"),
    in_routine: Optional[bool] = None,
    in_experiment: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    query = db.query(Product).filter(Product.user_id == current_user.id)
    if category:
        query = query.filter(Product.category == category)
    if status_filter:
        query = query.filter(Product.status == status_filter)
    if in_routine is not None:
        query = query.filter(Product.in_routine == in_routine)
    if in_experiment is not None:
        query = query.filter(Product.in_experiment == in_experiment)
    return query.order_by(Product.created_at.desc()).all()

@router.post("", response_model=ProductOut, status_code=status.HTTP_201_CREATED)
def create_product(
    payload: ProductCreate,
    response: Response = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
):
    key = header(request, "Idempotency-Key") if request is not None else None
    identifier = product_attempts.identity(current_user.id, key) if key is not None else None
    digest = product_attempts.fingerprint(payload) if key is not None else None
    lock_owner(db, current_user)
    if identifier is not None:
        replay = product_attempts.replay(db, current_user.id, identifier, digest, response)
        if replay is not None:
            return replay
    existing = db.query(Product).filter(
        Product.user_id == current_user.id,
        Product.name.ilike(payload.name)
    ).first()
    if existing:
        raise DermaireException(
            message=f"A product named '{payload.name}' already exists in your routine or library.",
            error_code="PRODUCT_DUPLICATE_NAME",
            status_code=status.HTTP_409_CONFLICT
        )

    product = Product(
        user_id=current_user.id,
        name=payload.name,
        brand=payload.brand,
        category=payload.category,
        product_type=payload.product_type,
        active_ingredients=payload.active_ingredients,
        skin_concerns=payload.skin_concerns,
        usage_instructions=payload.usage_instructions,
        frequency_per_week=payload.frequency_per_week,
        time_of_use=payload.time_of_use,
        status="active",
        tags=payload.tags,
        in_routine=payload.in_routine,
        in_experiment=payload.in_experiment,
        notes=payload.notes,
        start_date=payload.start_date
    )
    db.add(product)
    try:
        db.flush()
        result = ProductOut.model_validate(product)
        if identifier is not None:
            db.add(ProductCreateAttempt(id=identifier, user_id=current_user.id,
                resource_id=product.id, resource_revision=product.revision, payload_hash=digest,
                recorded_at=datetime.now(timezone.utc).replace(tzinfo=None),
                result_snapshot=result.model_dump(mode="json")))
        db.add(AuditLog(actor_id=current_user.id, action="PRODUCT_CREATED", target_resource="products",
            details={"product_id":product.id, "name":product.name}))
        db.commit()
    except IntegrityError:
        db.rollback()
        if identifier is not None:
            replay = product_attempts.replay(db, current_user.id, identifier, digest, response)
            if replay is not None:
                return replay
        raise HTTPException(503, "Product create outcome unavailable; reconcile the same attempt") from None
    except Exception:
        db.rollback()
        raise HTTPException(503, "Product create outcome unavailable; reconcile the same attempt") from None
    product_attempts.headers(response, identifier, result.revision)
    return result


@router.get("/attempts/{key}", response_model=ProductCreateAttemptOut)
def product_create_attempt(key: str, response: Response,
    current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    response.headers['Cache-Control'] = 'no-store'
    return product_attempts.lookup(db, current_user.id, key)


@router.get("/{product_id}/operation-attempts/{operation}/{key}")
def product_mutation_attempt(product_id: str, operation: str, key: str, response: Response,
    current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    response.headers['Cache-Control'] = 'no-store'
    return product_mutations.lookup(db, current_user.id, product_id, operation, key)


@router.get("/{product_id}", response_model=ProductOut)
def get_product(
    product_id: str,
    response: Response = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)
    if response is not None:
        response.headers["ETag"] = f'"{product.revision}"'
    return product

@router.patch("/{product_id}", response_model=ProductOut)
def update_product(
    product_id: str,
    payload: ProductUpdate,
    response: Response = None,
    if_match: str | None = Header(None, alias="If-Match", max_length=64),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
):
    lock_owner(db, current_user)
    key = header(request, "Idempotency-Key") if request is not None else None
    identifier = product_mutations.identity(current_user.id, product_id, "patch", key) if key is not None else None
    digest = product_mutations.fingerprint(product_id, "patch", payload, if_match) if identifier else None
    if request is not None:
        header(request)  # Duplicate preconditions are invalid even on replay.
    if identifier:
        replay = product_mutations.replay(db, current_user.id, identifier, digest, response)
        if replay is not None:
            return replay
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)

    if request is not None:
        header(request)  # Reject duplicate preconditions instead of selecting one.
    product_revisions.enforce(product, if_match)
    guard_routine_write(db, current_user.id)
    data = payload.model_dump(exclude_unset=True)
    required_fields = {"name", "category", "active_ingredients", "skin_concerns",
                       "usage_instructions", "frequency_per_week", "time_of_use",
                       "status", "in_routine", "in_experiment", "tags"}
    if any(key in data and data[key] is None for key in required_fields):
        raise DermaireException(message="Product fields cannot be null.", error_code="PRODUCT_INVALID_UPDATE", status_code=422)
    if "name" in data:
        existing = db.query(Product).filter(
            Product.user_id == current_user.id,
            Product.id != product.id,
            Product.name.ilike(data["name"])
        ).first()
        if existing:
            raise DermaireException(message="A product with this name already exists.", error_code="PRODUCT_DUPLICATE_NAME", status_code=409)
    if product.in_experiment and data.get("status") == "archived":
        raise DermaireException(message="Finish the experiment before archiving this product.", error_code="PRODUCT_IN_ACTIVE_EXPERIMENT", status_code=409)
    if data.get("status") is not None and data["status"] != "active" and db.query(RoutineEntry).filter_by(
            product_id=product.id, user_id=current_user.id, active=True, revision_protected=True).first():
        raise HTTPException(409, "Stop protected routine entries with their current If-Match before archiving the product")
    if if_match is not None:
        product.revision_protected = True
    for key, value in data.items():
        setattr(product, key, value)

    if product.status != "active":
        for entry in db.query(RoutineEntry).filter_by(product_id=product.id, user_id=current_user.id, active=True):
            deactivate(entry)
    db.add(AuditLog(actor_id=current_user.id, action="PRODUCT_UPDATED", target_resource="products",
        details={"product_id": product.id}))
    result = None
    if identifier:
        product_mutations.flush(db)  # Freeze resulting product and routine revisions in the same transaction.
        result = ProductOut.model_validate(product).model_dump(mode="json")
        product_mutations.stage(db, current_user.id, product.id, "patch", identifier, digest, product.revision, result)
    product_revisions.commit(db)
    if identifier:
        product_attempts.headers(response, identifier, result["revision"])
        return result
    db.refresh(product)
    if response is not None:
        response.headers["ETag"] = f'"{product.revision}"'
    return product

@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(
    product_id: str,
    if_match: str | None = Header(None, alias="If-Match", max_length=64),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None,
    response: Response = None
):
    lock_owner(db, current_user)
    key = header(request, "Idempotency-Key") if request is not None else None
    identifier = product_mutations.identity(current_user.id, product_id, "delete", key) if key is not None else None
    digest = product_mutations.fingerprint(product_id, "delete", None, if_match) if identifier else None
    if request is not None:
        header(request)
    if identifier:
        replay = product_mutations.replay(db, current_user.id, identifier, digest, response)
        if replay is not None:
            return
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)

    if request is not None:
        header(request)  # Reject duplicate preconditions instead of selecting one.
    product_revisions.enforce(product, if_match)

    if db.query(Experiment).filter_by(product_id=product.id).first():
        raise DermaireException(message="Archive this product to preserve experiment history.", error_code="PRODUCT_HAS_EXPERIMENT_HISTORY", status_code=409)
    if product.in_experiment:
        raise DermaireException(
            message="Cannot delete a product currently linked to an active skin experiment. Archive or finish the experiment first.",
            error_code="PRODUCT_IN_ACTIVE_EXPERIMENT",
            status_code=status.HTTP_409_CONFLICT
        )

    if db.query(RoutineEntry).filter_by(product_id=product.id).first():
        raise DermaireException(message="Archive this product to preserve routine history.", error_code="PRODUCT_HAS_ROUTINE_HISTORY", status_code=409)

    if db.query(ProductIntelligence.id).filter(
            ProductIntelligence.product_id == product.id,
            ProductIntelligence.user_id != current_user.id).first():
        raise DermaireException(message="Product links require repair before deletion.",
                               error_code="PRODUCT_INVALID_OWNERSHIP", status_code=409)
    # Reserve the revision before independent deletion journal intent. A stale
    # delete must not journal a product whose competing update already won.
    product.revision += 1
    try:
        db.flush()
    except StaleDataError:
        db.rollback()
        raise HTTPException(412, "Product changed or was deleted")
    try:
        deletion_journal.record_product(current_user.id, product.id)
    except Exception:
        db.rollback()
        raise DermaireException(message="Product deletion is temporarily unavailable.",
                               error_code="DELETION_UNAVAILABLE", status_code=503) from None
    db.query(ProductIntelligence).filter_by(product_id=product.id,
        user_id=current_user.id).delete(synchronize_session=False)
    product_attempts.erase_results(db, current_user.id, product.id)
    db.delete(product)
    db.add(AuditLog(actor_id=current_user.id, action="PRODUCT_DELETED", target_resource="products",
        details={"product_id": product_id}))
    if identifier:
        product_mutations.stage(db, current_user.id, product_id, "delete", identifier, digest, product.revision,
            {"deleted": True, "id": product_id, "revision": product.revision})
        product_attempts.headers(response, identifier, product.revision)
    product_revisions.commit(db)

@router.post("/check-interactions", deprecated=True)
def check_interactions_endpoint(payload: ProductInteractionCheckRequest, current_user: User = Depends(get_current_user)):
    raise DermaireException(message="Use authenticated product/routine intelligence; free-text compatibility checks are retired.", error_code="PRODUCT_INTELLIGENCE_REQUIRED", status_code=410)
