from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.exceptions import EntityNotFoundException, DermaireException
from app.api.deps import get_current_user, record_audit
from app.models import User, Product, RoutineEntry, Experiment, ProductIntelligence
from app.services.deletion_journal import deletion_journal
from app.services.experiments import guard_routine_write
from app.services.routine import lock_owner, deactivate
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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
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

    db.commit()
    db.refresh(product)

    record_audit(db, current_user.id, "PRODUCT_CREATED", "products", {"product_id": product.id, "name": product.name})
    return product

@router.get("/{product_id}", response_model=ProductOut)
def get_product(
    product_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)
    return product

@router.patch("/{product_id}", response_model=ProductOut)
def update_product(
    product_id: str,
    payload: ProductUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    lock_owner(db, current_user)
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)

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
    for key, value in data.items():
        setattr(product, key, value)

    if product.status != "active":
        for entry in db.query(RoutineEntry).filter_by(product_id=product.id, user_id=current_user.id, active=True):
            deactivate(entry)
    db.commit()
    db.refresh(product)
    record_audit(db, current_user.id, "PRODUCT_UPDATED", "products", {"product_id": product.id})
    return product

@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(
    product_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    lock_owner(db, current_user)
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.user_id == current_user.id
    ).first()
    if not product:
        raise EntityNotFoundException("Product", product_id)

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
    try:
        deletion_journal.record_product(current_user.id, product.id)
    except Exception:
        db.rollback()
        raise DermaireException(message="Product deletion is temporarily unavailable.",
                               error_code="DELETION_UNAVAILABLE", status_code=503) from None
    db.query(ProductIntelligence).filter_by(product_id=product.id,
        user_id=current_user.id).delete(synchronize_session=False)
    db.delete(product)
    db.commit()
    record_audit(db, current_user.id, "PRODUCT_DELETED", "products", {"product_id": product_id})

@router.post("/check-interactions", deprecated=True)
def check_interactions_endpoint(payload: ProductInteractionCheckRequest, current_user: User = Depends(get_current_user)):
    raise DermaireException(message="Use authenticated product/routine intelligence; free-text compatibility checks are retired.", error_code="PRODUCT_INTELLIGENCE_REQUIRED", status_code=410)
