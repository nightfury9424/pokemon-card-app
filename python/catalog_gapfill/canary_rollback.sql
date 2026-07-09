DELETE FROM price_snapshots WHERE price_snapshot_id LIKE 'BFILL_%';
-- DELETE FROM cards WHERE card_id IN (<canary card_ids>);
DELETE FROM products WHERE product_id='PRD_C415EEEB7B1D687E78403';
