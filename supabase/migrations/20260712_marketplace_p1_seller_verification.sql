-- =========================================================================
-- MARKETPLACE P1.3: SELLER VERIFICATION & PRODUCT MODERATION
-- Adds verification requests, product reports/moderation
-- =========================================================================

-- 1. Seller verification requests table
CREATE TABLE IF NOT EXISTS seller_verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    business_name TEXT NOT NULL,
    business_type TEXT NOT NULL,
    business_registration_number TEXT,
    tax_id TEXT,
    id_document_url TEXT, -- Link to uploaded ID/passport
    business_document_url TEXT, -- Business registration certificate
    bank_account_info JSONB, -- Encrypted bank details
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected')),
    rejection_reason TEXT,
    reviewed_by UUID REFERENCES profiles(id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(seller_id)
);

CREATE INDEX IF NOT EXISTS idx_verification_requests_seller_id ON seller_verification_requests(seller_id);
CREATE INDEX IF NOT EXISTS idx_verification_requests_status ON seller_verification_requests(status);

-- 2. Product reports table
CREATE TABLE IF NOT EXISTS product_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reason TEXT NOT NULL CHECK (reason IN ('spam', 'fake', 'inappropriate', 'wrong_category', 'misleading', 'other')),
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed')),
    moderator_id UUID REFERENCES profiles(id),
    moderator_notes TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_product_reports_product_id ON product_reports(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reports_status ON product_reports(status);
CREATE INDEX IF NOT EXISTS idx_product_reports_reporter_id ON product_reports(reporter_id);

-- 3. Add moderation fields to products table (if not exist)
DO $$ 
BEGIN
    -- moderation_status
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'moderation_status'
    ) THEN
        ALTER TABLE products ADD COLUMN moderation_status TEXT DEFAULT 'approved' 
            CHECK (moderation_status IN ('pending', 'approved', 'rejected', 'flagged'));
    END IF;

    -- moderation_notes
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'moderation_notes'
    ) THEN
        ALTER TABLE products ADD COLUMN moderation_notes TEXT;
    END IF;

    -- moderated_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'moderated_at'
    ) THEN
        ALTER TABLE products ADD COLUMN moderated_at TIMESTAMPTZ;
    END IF;

    -- moderated_by
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'products' AND column_name = 'moderated_by'
    ) THEN
        ALTER TABLE products ADD COLUMN moderated_by UUID REFERENCES profiles(id);
    END IF;
END $$;

-- 4. Product review helpful votes table
CREATE TABLE IF NOT EXISTS review_helpful_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES product_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(review_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_review_helpful_votes_review_id ON review_helpful_votes(review_id);
CREATE INDEX IF NOT EXISTS idx_review_helpful_votes_user_id ON review_helpful_votes(user_id);

-- 5. Add helpful_count to product_reviews (if not exist)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'product_reviews' AND column_name = 'helpful_count'
    ) THEN
        ALTER TABLE product_reviews ADD COLUMN helpful_count INTEGER DEFAULT 0;
    END IF;
END $$;

-- 6. Trigger to update helpful_count
CREATE OR REPLACE FUNCTION update_review_helpful_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE product_reviews 
        SET helpful_count = helpful_count + 1 
        WHERE id = NEW.review_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE product_reviews 
        SET helpful_count = GREATEST(helpful_count - 1, 0)
        WHERE id = OLD.review_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_review_helpful_count ON review_helpful_votes;
CREATE TRIGGER trigger_update_review_helpful_count
    AFTER INSERT OR DELETE ON review_helpful_votes
    FOR EACH ROW EXECUTE FUNCTION update_review_helpful_count();

-- 7. RLS Policies
ALTER TABLE seller_verification_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_helpful_votes ENABLE ROW LEVEL SECURITY;

-- Verification requests: sellers can view their own, admins can view all
CREATE POLICY verification_requests_select ON seller_verification_requests FOR SELECT
    USING (
        auth.uid() = user_id OR 
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
    );

CREATE POLICY verification_requests_insert ON seller_verification_requests FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Product reports: reporters and admins can view
CREATE POLICY product_reports_select ON product_reports FOR SELECT
    USING (
        auth.uid() = reporter_id OR 
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
    );

CREATE POLICY product_reports_insert ON product_reports FOR INSERT
    WITH CHECK (auth.uid() = reporter_id);

-- Review helpful votes: users can manage their own votes
CREATE POLICY review_helpful_votes_select ON review_helpful_votes FOR SELECT
    USING (true);

CREATE POLICY review_helpful_votes_insert ON review_helpful_votes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY review_helpful_votes_delete ON review_helpful_votes FOR DELETE
    USING (auth.uid() = user_id);

-- 8. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- MIGRATION COMPLETE
-- Tables: seller_verification_requests, product_reports, review_helpful_votes
-- Products: moderation_status, moderation_notes, moderated_at, moderated_by
-- Reviews: helpful_count with trigger
-- =========================================================================
