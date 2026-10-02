"""Deterministic positive evidence only. Absence of warnings never means compatibility."""
from itertools import combinations
from app.models import ProductIntelligence, Product, RoutineEntry
from app.schemas.product_intelligence import IntelligenceDocument

VERSION = "product-intelligence-1.0"
# Exact aliases only. Distinct molecules stay distinct; classes are separate metadata.
ACTIVES = {
    "niacinamide": ("Niacinamide", None, ["nicotinamide"]),
    "retinol": ("Retinol", "retinoid", []),
    "retinal": ("Retinal", "retinoid", ["retinaldehyde"]),
    "tretinoin": ("Tretinoin", "retinoid", ["retinoic acid", "all-trans retinoic acid"]),
    "adapalene": ("Adapalene", "retinoid", []),
    "glycolic_acid": ("Glycolic acid", "exfoliant", []),
    "lactic_acid": ("Lactic acid", "exfoliant", []),
    "mandelic_acid": ("Mandelic acid", "exfoliant", []),
    "salicylic_acid": ("Salicylic acid", "exfoliant", []),
    "azelaic_acid": ("Azelaic acid", None, []),
    "benzoyl_peroxide": ("Benzoyl peroxide", None, []),
    "ascorbic_acid": ("Ascorbic acid", None, ["l-ascorbic acid"]),
}
ALIASES = {alias.casefold(): key for key, (name, _, aliases) in ACTIVES.items()
           for alias in [name, *aliases]}
ALIASES.update({"parfum": "fragrance", "fragrance": "fragrance", "perfume": "fragrance", "عطر": "fragrance"})
RULE_SOURCE = "https://www.aad.org/public/everyday-care/skin-care-secrets/routine/safely-exfoliate-at-home"
LIMITATIONS = ["Informational only; no diagnosis, treatment or compatibility assessment.",
               "Unknown concentrations, formulation, exposure and individual response limit interpretation.",
               "No warning does not establish safety; only the documented v1 rules are checked."]


def ingredient_key(name):
    cleaned = " ".join(name.strip().casefold().split())
    return ALIASES.get(cleaned, cleaned)


def read_intelligence(db, product):
    row = db.query(ProductIntelligence).filter_by(product_id=product.id, user_id=product.user_id).first()
    if row:
        document = IntelligenceDocument.model_validate(row.document).model_dump(mode="json")
        updated_at = row.updated_at.isoformat()
    else:
        # Legacy fields are explicit user reports, never independent verification.
        source = {"id": "saved_user_report", "type": "user_reported", "reference": "Saved product fields",
                  "verification": "unverified", "confidence": "low", "last_verified_at": None}
        document = {"sources": [source]}
        for field, value in (("canonical_name", product.name), ("brand", product.brand), ("category", product.category), ("product_type", product.product_type)):
            document[field] = {"value": value, "source_id": source["id"]} if value else None
        document["ingredients"] = {"source_id": source["id"], "completeness": "partial", "items": [
            {"name": name, "source_id": source["id"], "position": None, "strength": None}
            for name in (product.active_ingredients or []) if isinstance(name, str) and name.strip()
        ]} if product.active_ingredients else None
        updated_at = product.updated_at.isoformat() if product.updated_at else None
    sources = {source["id"]: source for source in document["sources"]}
    ingredients = document.get("ingredients")
    normalized = []
    seen = set()
    items = list(enumerate((ingredients or {}).get("items", [])))
    if items and all(item.get("position") is not None for _, item in items):
        items.sort(key=lambda pair: pair[1]["position"])
    for index, item in items:
        key = ingredient_key(item["name"])
        if key in seen:
            continue  # Legacy reports may repeat aliases; do not multiply warnings.
        seen.add(key)
        normalized.append({**item, "ingredient_ref": f"{product.id}:{index}", "normalized_key": key,
                           "normalized_name": ACTIVES[key][0] if key in ACTIVES else key,
                           "active_class": ACTIVES[key][1] if key in ACTIVES else None,
                           "is_supported_active": key in ACTIVES,
                           "concentration_state": "known" if item.get("strength") else "unknown",
                           "evidence": sources[item["source_id"]]})
    unknowns = [field for field in ("region", "formulation_variant", "manufacturer", "dosage_form", "formulation_text")
                if not document.get(field)]
    if not ingredients or ingredients["completeness"] != "complete":
        unknowns.append("complete_ingredient_list")
    complete = bool(ingredients and ingredients["completeness"] == "complete")
    return {"version": VERSION, "product_id": product.id, "state": "unknown" if not normalized else "facts_available",
            "data_completeness": "complete" if complete else "incomplete", "unknowns": unknowns,
            "facts": document, "ingredients": normalized,
            "actives": [item for item in normalized if item["is_supported_active"]],
            "updated_at": updated_at, "limitations": LIMITATIONS}


def warnings_for(products, disclosures):
    warnings = []
    def add(key, explanation, refs, rule_source=None, disclosure=None):
        evidence = [{"product_id": p["product_id"], "ingredient_ref": i["ingredient_ref"],
                     "normalized_key": i["normalized_key"], "source": i["evidence"]} for p, i in refs]
        bands = {"unknown": 0, "low": 1, "medium": 2, "high": 3}
        confidence = min((e["source"]["confidence"] for e in evidence), key=lambda c: bands[c])
        warnings.append({"key": key, "severity": "info" if key == "duplicate_active" else "caution",
                         "explanation": explanation, "evidence": evidence, "confidence": confidence,
                         "data_completeness": "complete" if all(p["data_completeness"] == "complete" for p, _ in refs) else "incomplete",
                         "limitations": LIMITATIONS, "rule_source": rule_source, "disclosure": disclosure})
    for a, b in combinations(products, 2):
        for ia, ib in combinations_for_products(a, b):
            keys = [ia["normalized_key"], ib["normalized_key"]]
            classes = [ia["active_class"], ib["active_class"]]
            refs = [(a, ia), (b, ib)]
            if keys[0] == keys[1] and ia["is_supported_active"]:
                add("duplicate_active", "Two routine products report the same active ingredient.", refs)
            elif classes[0] == classes[1] and classes[0] in ("retinoid", "exfoliant"):
                add("duplicate_" + classes[0] + "_class", "Multiple routine products report ingredients in the same " + classes[0] + " class; combined exposure is unknown.", refs)
    # Check same-product and cross-product pairs, without claiming schedules imply co-application.
    all_refs = [(p, i) for p in products for i in p["actives"]]
    for (a, ia), (b, ib) in combinations(all_refs, 2):
        if {ia["active_class"], ib["active_class"]} == {"retinoid", "exfoliant"}:
            add("retinoid_exfoliant_caution", "Retinoid and exfoliant ingredients are reported in the available product facts. Combined use may increase irritation risk; actual co-application and formulation effects are unknown.", [(a, ia), (b, ib)], RULE_SOURCE)
    for p in products:
        for i in p["ingredients"]:
            for disclosure in disclosures or []:
                if ingredient_key(disclosure) == i["normalized_key"]:
                    add("disclosed_sensitivity_match", "A reported ingredient matches an explicitly disclosed sensitivity/allergy. This does not confirm an allergic reaction.", [(p, i)], disclosure=disclosure)
    return warnings


def combinations_for_products(a, b):
    return ((ia, ib) for ia in a["actives"] for ib in b["actives"])


def routine_intelligence(db, user):
    # Routine entries, not legacy in_routine markers, define current participation.
    rows = db.query(Product).join(RoutineEntry, RoutineEntry.product_id == Product.id).filter(
        Product.user_id == user.id, Product.status == "active", RoutineEntry.user_id == user.id,
        RoutineEntry.active.is_(True)).order_by(Product.id).distinct().all()
    products = [read_intelligence(db, product) for product in rows]
    return {"version": VERSION, "products": products,
            "warnings": warnings_for(products, (user.profile_context or {}).get("sensitivities_allergies")),
            "data_completeness": "complete" if products and all(p["data_completeness"] == "complete" for p in products) else "incomplete",
            "limitations": LIMITATIONS}
