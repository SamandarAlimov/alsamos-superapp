-- =========================================================================
-- MARKETPLACE P2: ADVANCED SEARCH + NOTIFICATIONS
-- PostgreSQL full-text search, filters, marketplace notifications
-- =========================================================================

-- 1. Add full-text search columns to products (if not exist)
DO $$ 
BEGIN
    -- search_vector for tsvector
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'search_vector'
    ) THEN
        ALTER TABLE products ADD COLUMN search_vector tsvector;
    END IF;

    -- tags array
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'tags'
    ) THEN
        ALTER TABLE products ADD COLUMN tags TEXT[] DEFAULT '{}';
    END IF;
END $$;

-- 2. Create GIN index for full-text search
CREATE INDEX IF NOT EXISTS idx_products_search_vector ON products USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_products_tags ON products USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);
CREATE INDEX IF NOT EXISTS idx_products_condition ON products(condition);
CREATE INDEX IF NOT EXISTS idx_products_location ON products(location);

-- 3. Function to update search_vector
CREATE OR REPLACE FUNCTION products_search_vector_update()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := 
        setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(array_to_string(NEW.tags, ' '), '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_products_search_vector ON products;
CREATE TRIGGER trigger_products_search_vector
    BEFORE INSERT OR UPDATE OF title, description, tags
    ON products
    FOR EACH ROW EXECUTE FUNCTION products_search_vector_update();

-- 4. Update existing products with search_vector
UPDATE products 
SET search_vector = 
    setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(description, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(array_to_string(tags, ' '), '')), 'C')
WHERE search_vector IS NULL;

-- 5. Search history table
CREATE TABLE IF NOT EXISTS product_search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    results_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON product_search_history(user_id);
CREATE INDEX IF NOT EXISTS idx_search_history_created_at ON product_search_history(created_at DESC);

-- 6. Popular searches (aggregated view)
CREATE MATERIALIZED VIEW IF NOT EXISTS popular_product_searches AS
SELECT 
    query,
    COUNT(*) as search_count,
    MAX(created_at) as last_searched_at
FROM product_search_history
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY query
ORDER BY search_count DESC
LIMIT 100;

CREATE UNIQUE INDEX IF NOT EXISTS idx_popular_searches_query ON popular_product_searches(query);

-- Refresh materialized view daily
CREATE OR REPLACE FUNCTION refresh_popular_searches()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY popular_product_searches;
END;
$$ LANGUAGE plpgsql;

-- 7. Marketplace notifications table
CREATE TABLE IF NOT EXISTS marketplace_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('new_order', 'order_status', 'price_drop', 'restock', 'seller_message', 'review', 'promotion')),
    title TEXT NOT NULL,
    body TEXT,
    data JSONB, -- Additional structured data (order_id, product_id, etc.)
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    action_url TEXT, -- Deep link to relevant page
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_user_id ON marketplace_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_type ON marketplace_notifications(type);
CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_is_read ON marketplace_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_marketplace_notifications_created_at ON marketplace_notifications(created_at DESC);

-- 8. Product price alerts (for price drop notifications)
CREATE TABLE IF NOT EXISTS product_price_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    target_price NUMERIC(12,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_price_alerts_user_id ON product_price_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_price_alerts_product_id ON product_price_alerts(product_id);
CREATE INDEX IF NOT EXISTS idx_price_alerts_active ON product_price_alerts(is_active) WHERE is_active = true;

-- 9. Wishlist sharing table
CREATE TABLE IF NOT EXISTS shared_wishlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    share_code TEXT UNIQUE NOT NULL,
    product_ids UUID[] DEFAULT '{}',
    views_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shared_wishlists_owner_id ON shared_wishlists(owner_id);
CREATE INDEX IF NOT EXISTS idx_shared_wishlists_share_code ON shared_wishlists(share_code);

-- 10. Function to generate share code
CREATE OR REPLACE FUNCTION generate_share_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 11. RLS Policies
ALTER TABLE product_search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_price_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_wishlists ENABLE ROW LEVEL SECURITY;

-- Search history: users see their own
CREATE POLICY search_history_select ON product_search_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY search_history_insert ON product_search_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Marketplace notifications: users see their own
CREATE POLICY marketplace_notifications_select ON marketplace_notifications FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY marketplace_notifications_update ON marketplace_notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- Price alerts: users manage their own
CREATE POLICY price_alerts_select ON product_price_alerts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY price_alerts_insert ON product_price_alerts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY price_alerts_update ON product_price_alerts FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY price_alerts_delete ON product_price_alerts FOR DELETE
    USING (auth.uid() = user_id);

-- Shared wishlists: owner sees all, others see public
CREATE POLICY shared_wishlists_select ON shared_wishlists FOR SELECT
    USING (auth.uid() = owner_id OR is_public = true);

CREATE POLICY shared_wishlists_insert ON shared_wishlists FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY shared_wishlists_update ON shared_wishlists FOR UPDATE
    USING (auth.uid() = owner_id);

CREATE POLICY shared_wishlists_delete ON shared_wishlists FOR DELETE
    USING (auth.uid() = owner_id);

-- 12. Function to send marketplace notification
CREATE OR REPLACE FUNCTION send_marketplace_notification(
    p_user_id UUID,
    p_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT NULL,
    p_action_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    INSERT INTO marketplace_notifications (user_id, type, title, body, data, action_url)
    VALUES (p_user_id, p_type, p_title, p_body, p_data, p_action_url)
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 13. Trigger to check price drops and send notifications
CREATE OR REPLACE FUNCTION check_price_drop_alerts()
RETURNS TRIGGER AS $$
DECLARE
    alert RECORD;
BEGIN
    -- Only if price decreased
    IF TG_OP = 'UPDATE' AND NEW.price < OLD.price THEN
        -- Find all active price alerts for this product
        FOR alert IN 
            SELECT * FROM product_price_alerts 
            WHERE product_id = NEW.id 
            AND is_active = true 
            AND target_price >= NEW.price
            AND (notified_at IS NULL OR notified_at < NOW() - INTERVAL '7 days')
        LOOP
            -- Send notification
            PERFORM send_marketplace_notification(
                alert.user_id,
                'price_drop',
                'Narx tushdi!',
                NEW.title || ' narxi tushdi: ' || NEW.price::TEXT || ' ' || NEW.currency,
                jsonb_build_object('product_id', NEW.id, 'old_price', OLD.price, 'new_price', NEW.price),
                '/marketplace/product/' || NEW.id
            );
            
            -- Update notified_at
            UPDATE product_price_alerts 
            SET notified_at = NOW() 
            WHERE id = alert.id;
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_price_drop_alerts ON products;
CREATE TRIGGER trigger_check_price_drop_alerts
    AFTER UPDATE OF price ON products
    FOR EACH ROW EXECUTE FUNCTION check_price_drop_alerts();

-- 14. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- MIGRATION COMPLETE
-- Search: search_vector, tags, GIN indexes, search history, popular searches
-- Notifications: marketplace_notifications, price_alerts, wishlist sharing
-- Functions: send_marketplace_notification, price drop trigger
-- =========================================================================
