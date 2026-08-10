-- =========================================================================
-- MARKETPLACE P3: SELLER ANALYTICS + INVENTORY MANAGEMENT
-- Analytics views, inventory tracking, variant management
-- =========================================================================

-- 1. Seller analytics view (aggregated metrics)
CREATE OR REPLACE VIEW seller_analytics AS
SELECT 
    s.id as seller_id,
    s.business_name,
    s.user_id,
    
    -- Product metrics
    COUNT(DISTINCT p.id) as total_products,
    COUNT(DISTINCT p.id) FILTER (WHERE p.status = 'active') as active_products,
    SUM(p.views_count) as total_views,
    SUM(p.likes_count) as total_likes,
    
    -- Order metrics
    COUNT(DISTINCT o.id) as total_orders,
    COUNT(DISTINCT o.id) FILTER (WHERE o.status = 'delivered') as completed_orders,
    COUNT(DISTINCT o.id) FILTER (WHERE o.status IN ('pending', 'processing')) as pending_orders,
    SUM(o.total) FILTER (WHERE o.status = 'delivered') as total_revenue,
    AVG(o.total) FILTER (WHERE o.status = 'delivered') as avg_order_value,
    
    -- Customer metrics
    COUNT(DISTINCT o.buyer_id) as total_customers,
    COUNT(DISTINCT o.buyer_id) FILTER (WHERE o.created_at > NOW() - INTERVAL '30 days') as active_customers_30d,
    
    -- Review metrics
    COUNT(DISTINCT pr.id) as total_reviews,
    AVG(pr.rating) as avg_rating,
    
    -- Conversion metrics
    CASE 
        WHEN SUM(p.views_count) > 0 
        THEN (COUNT(DISTINCT o.id)::FLOAT / SUM(p.views_count) * 100)
        ELSE 0 
    END as conversion_rate,
    
    -- Time periods
    MAX(o.created_at) as last_order_at,
    MAX(p.created_at) as last_product_at
    
FROM sellers s
LEFT JOIN products p ON p.seller_id = s.id AND p.status != 'deleted'
LEFT JOIN orders o ON o.seller_id = s.id
LEFT JOIN product_reviews pr ON pr.product_id = p.id
GROUP BY s.id, s.business_name, s.user_id;

-- 2. Product performance view
CREATE OR REPLACE VIEW product_performance AS
SELECT 
    p.id as product_id,
    p.seller_id,
    p.title,
    p.price,
    p.quantity,
    p.views_count,
    p.likes_count,
    
    -- Order metrics
    COUNT(DISTINCT oi.order_id) as times_sold,
    SUM(oi.quantity) as units_sold,
    SUM(oi.total) as revenue,
    
    -- Review metrics
    COUNT(DISTINCT pr.id) as review_count,
    AVG(pr.rating) as avg_rating,
    
    -- Conversion
    CASE 
        WHEN p.views_count > 0 
        THEN (COUNT(DISTINCT oi.order_id)::FLOAT / p.views_count * 100)
        ELSE 0 
    END as conversion_rate,
    
    -- Last activity
    MAX(oi.created_at) as last_sold_at,
    p.created_at as listed_at,
    p.updated_at
    
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
LEFT JOIN product_reviews pr ON pr.product_id = p.id
WHERE p.status != 'deleted'
GROUP BY p.id, p.seller_id, p.title, p.price, p.quantity, p.views_count, p.likes_count, p.created_at, p.updated_at;

-- 3. Inventory management fields
DO $$ 
BEGIN
    -- sku (stock keeping unit)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'sku'
    ) THEN
        ALTER TABLE products ADD COLUMN sku TEXT UNIQUE;
    END IF;

    -- low_stock_threshold
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'low_stock_threshold'
    ) THEN
        ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER DEFAULT 5;
    END IF;

    -- variants (JSON array for size/color variations)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'variants'
    ) THEN
        ALTER TABLE products ADD COLUMN variants JSONB DEFAULT '[]';
    END IF;

    -- last_restocked_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'last_restocked_at'
    ) THEN
        ALTER TABLE products ADD COLUMN last_restocked_at TIMESTAMPTZ;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_low_stock ON products(quantity) WHERE quantity <= low_stock_threshold;

-- 4. Inventory alerts table
CREATE TABLE IF NOT EXISTS inventory_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL CHECK (alert_type IN ('low_stock', 'out_of_stock', 'restock_reminder')),
    current_quantity INTEGER NOT NULL,
    threshold INTEGER,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(product_id, alert_type, is_resolved)
);

CREATE INDEX IF NOT EXISTS idx_inventory_alerts_product_id ON inventory_alerts(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_alerts_seller_id ON inventory_alerts(seller_id);
CREATE INDEX IF NOT EXISTS idx_inventory_alerts_unresolved ON inventory_alerts(is_resolved) WHERE is_resolved = false;

-- 5. Function to check and create inventory alerts
CREATE OR REPLACE FUNCTION check_inventory_alerts()
RETURNS TRIGGER AS $$
DECLARE
    v_seller_id UUID;
BEGIN
    -- Get seller_id
    SELECT seller_id INTO v_seller_id FROM products WHERE id = NEW.id;
    
    -- Low stock alert
    IF NEW.quantity > 0 AND NEW.quantity <= NEW.low_stock_threshold THEN
        INSERT INTO inventory_alerts (product_id, seller_id, alert_type, current_quantity, threshold)
        VALUES (NEW.id, v_seller_id, 'low_stock', NEW.quantity, NEW.low_stock_threshold)
        ON CONFLICT (product_id, alert_type, is_resolved) WHERE is_resolved = false DO NOTHING;
    END IF;
    
    -- Out of stock alert
    IF NEW.quantity = 0 THEN
        INSERT INTO inventory_alerts (product_id, seller_id, alert_type, current_quantity, threshold)
        VALUES (NEW.id, v_seller_id, 'out_of_stock', 0, NULL)
        ON CONFLICT (product_id, alert_type, is_resolved) WHERE is_resolved = false DO NOTHING;
        
        -- Mark low_stock as resolved
        UPDATE inventory_alerts 
        SET is_resolved = true, resolved_at = NOW() 
        WHERE product_id = NEW.id AND alert_type = 'low_stock' AND is_resolved = false;
    END IF;
    
    -- Restocked - resolve all alerts
    IF TG_OP = 'UPDATE' AND NEW.quantity > OLD.quantity AND NEW.quantity > NEW.low_stock_threshold THEN
        UPDATE inventory_alerts 
        SET is_resolved = true, resolved_at = NOW() 
        WHERE product_id = NEW.id AND is_resolved = false;
        
        UPDATE products 
        SET last_restocked_at = NOW() 
        WHERE id = NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_inventory_alerts ON products;
CREATE TRIGGER trigger_check_inventory_alerts
    AFTER INSERT OR UPDATE OF quantity ON products
    FOR EACH ROW EXECUTE FUNCTION check_inventory_alerts();

-- 6. Traffic sources table (for analytics)
CREATE TABLE IF NOT EXISTS product_traffic_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    source TEXT NOT NULL, -- 'search', 'category', 'direct', 'recommendation', 'external'
    referrer TEXT,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    session_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_traffic_sources_product_id ON product_traffic_sources(product_id);
CREATE INDEX IF NOT EXISTS idx_traffic_sources_source ON product_traffic_sources(source);
CREATE INDEX IF NOT EXISTS idx_traffic_sources_created_at ON product_traffic_sources(created_at DESC);

-- 7. Customer demographics view (for seller analytics)
CREATE OR REPLACE VIEW seller_customer_demographics AS
SELECT 
    o.seller_id,
    COUNT(DISTINCT o.buyer_id) as total_customers,
    
    -- Order frequency segments
    COUNT(DISTINCT o.buyer_id) FILTER (WHERE buyer_order_count = 1) as one_time_customers,
    COUNT(DISTINCT o.buyer_id) FILTER (WHERE buyer_order_count >= 2 AND buyer_order_count <= 5) as repeat_customers,
    COUNT(DISTINCT o.buyer_id) FILTER (WHERE buyer_order_count > 5) as loyal_customers,
    
    -- Geographic distribution
    jsonb_object_agg(
        COALESCE((o.shipping_address->>'city'), 'Unknown'),
        city_count
    ) as cities,
    
    -- Average customer value
    AVG(customer_total_spent) as avg_customer_lifetime_value,
    MAX(customer_total_spent) as max_customer_lifetime_value
    
FROM orders o
CROSS JOIN LATERAL (
    SELECT 
        COUNT(*) as buyer_order_count,
        SUM(total) as customer_total_spent
    FROM orders o2 
    WHERE o2.buyer_id = o.buyer_id AND o2.seller_id = o.seller_id
) buyer_stats
CROSS JOIN LATERAL (
    SELECT COUNT(*) as city_count
    FROM orders o3
    WHERE o3.seller_id = o.seller_id 
    AND (o3.shipping_address->>'city') = (o.shipping_address->>'city')
) city_stats
GROUP BY o.seller_id;

-- 8. RLS Policies
ALTER TABLE inventory_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_traffic_sources ENABLE ROW LEVEL SECURITY;

-- Inventory alerts: seller sees their own
CREATE POLICY inventory_alerts_select ON inventory_alerts FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM sellers 
            WHERE sellers.id = inventory_alerts.seller_id 
            AND sellers.user_id = auth.uid()
        )
    );

-- Traffic sources: public read (analytics)
CREATE POLICY traffic_sources_select ON product_traffic_sources FOR SELECT
    USING (true);

CREATE POLICY traffic_sources_insert ON product_traffic_sources FOR INSERT
    WITH CHECK (true);

-- 9. Function to generate SKU
CREATE OR REPLACE FUNCTION generate_sku(p_category_id UUID, p_seller_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_category_code TEXT;
    v_seller_code TEXT;
    v_counter INTEGER;
    v_sku TEXT;
BEGIN
    -- Get category code (first 3 chars of category name)
    SELECT UPPER(LEFT(REPLACE(name, ' ', ''), 3)) INTO v_category_code
    FROM product_categories WHERE id = p_category_id;
    
    v_category_code := COALESCE(v_category_code, 'GEN');
    
    -- Get seller code (first 3 chars of business name)
    SELECT UPPER(LEFT(REPLACE(business_name, ' ', ''), 3)) INTO v_seller_code
    FROM sellers WHERE id = p_seller_id;
    
    v_seller_code := COALESCE(v_seller_code, 'SEL');
    
    -- Get next counter
    SELECT COUNT(*) + 1 INTO v_counter
    FROM products WHERE seller_id = p_seller_id;
    
    -- Generate SKU: CAT-SEL-0001
    v_sku := v_category_code || '-' || v_seller_code || '-' || LPAD(v_counter::TEXT, 4, '0');
    
    RETURN v_sku;
END;
$$ LANGUAGE plpgsql;

-- 10. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- MIGRATION COMPLETE
-- Analytics: seller_analytics view, product_performance view, customer_demographics
-- Inventory: sku, low_stock_threshold, variants, inventory_alerts with triggers
-- Traffic: product_traffic_sources for analytics
-- Functions: generate_sku, check_inventory_alerts
-- =========================================================================
