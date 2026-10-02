from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, require_role
from app.core.database import get_db
from app.models import Product, ProductIntelligence, User
from app.schemas.product_intelligence import IntelligenceDocument
from app.services.product_intelligence import read_intelligence, routine_intelligence, warnings_for, ingredient_key
from app.services.routine import lock_owner

router = APIRouter(tags=["Product Intelligence"])


@router.get("/products/{product_id}/intelligence")
def read(product_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    product = db.query(Product).filter_by(id=product_id, user_id=user.id).first()
    if product is None:
        raise HTTPException(404, "Product not found")
    result = read_intelligence(db, product)
    result["warnings"] = warnings_for([result], (user.profile_context or {}).get("sensitivities_allergies"))
    return result


@router.get("/routine/intelligence")
def routine(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return routine_intelligence(db, user)


@router.put("/admin/product-intelligence/{product_id}")
def ingest(product_id: str, payload: IntelligenceDocument, admin: User = Depends(require_role(["admin"])), db: Session = Depends(get_db)):
    if payload.ingredients:
        keys = [ingredient_key(item.name) for item in payload.ingredients.items]
        if len(keys) != len(set(keys)):
            raise HTTPException(422, "Ingredient identities must be unique (including aliases)")
    product = db.query(Product).filter_by(id=product_id).first()
    if product is None:
        raise HTTPException(404, "Product not found")
    owner = db.get(User, product.user_id)
    if owner is None:
        raise HTTPException(404, "Product owner not found")
    lock_owner(db, owner)
    # Re-read after acquiring the owner's lifecycle lock.
    product = db.query(Product).filter_by(id=product_id).populate_existing().first()
    if product is None:
        raise HTTPException(404, "Product not found")
    row = db.query(ProductIntelligence).filter_by(product_id=product_id).first()
    if row is None:
        row = ProductIntelligence(user_id=product.user_id, product_id=product_id)
        db.add(row)
    row.document = payload.model_dump(mode="json")
    try:
        db.commit()
        db.refresh(row)
    except Exception:
        db.rollback()
        raise HTTPException(503, "Intelligence write unavailable; refresh before retrying")
    return read_intelligence(db, product)
