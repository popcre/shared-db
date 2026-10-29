-- DesignFlow factory area, #4708 / claim #4749 (placeholder while the claim transfers; full body follows)
create table if not exists core.product_category (id uuid primary key default gen_random_uuid());
