-- Apply before deploying Product Intelligence v1. No seeded product facts.
BEGIN;
CREATE TABLE product_intelligence (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES users(id),
    product_id VARCHAR(36) NOT NULL UNIQUE REFERENCES products(id) ON DELETE CASCADE,
    document JSON NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
CREATE INDEX ix_product_intelligence_user_id ON product_intelligence(user_id);
COMMIT;
