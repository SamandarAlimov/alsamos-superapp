-- =========================================================================
-- MARKETPLACE P0.1: PAYMENTS + ESCROW SYSTEM
-- Project: mbhjganbihamoiqmankv
-- Schema: Adds escrow_holds, payment_gateway tables, wallet transaction RPCs
-- All operations idempotent (IF NOT EXISTS)
-- =========================================================================

-- 1. Escrow holds table (holds funds until delivery confirmation)
CREATE TABLE IF NOT EXISTS escrow_holds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'UZS',
    status TEXT NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'released', 'refunded', 'cancelled')),
    release_at TIMESTAMPTZ, -- Auto-release date
    released_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_escrow_holds_order_id ON escrow_holds(order_id);
CREATE INDEX IF NOT EXISTS idx_escrow_holds_user_id ON escrow_holds(user_id);
CREATE INDEX IF NOT EXISTS idx_escrow_holds_status ON escrow_holds(status);
CREATE INDEX IF NOT EXISTS idx_escrow_holds_release_at ON escrow_holds(release_at) WHERE status = 'held';

-- 2. Payment gateway transactions (external payments: Click, Payme, etc.)
CREATE TABLE IF NOT EXISTS payment_gateway_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    gateway TEXT NOT NULL CHECK (gateway IN ('wallet', 'click', 'payme', 'uzcard', 'humo', 'visa', 'mastercard')),
    gateway_transaction_id TEXT, -- External gateway transaction ID
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'UZS',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled', 'refunded')),
    payment_url TEXT, -- Redirect URL for external gateway
    callback_data JSONB, -- Gateway webhook data
    error_message TEXT,
    completed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_gateway_order_id ON payment_gateway_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_gateway_user_id ON payment_gateway_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_gateway_status ON payment_gateway_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_gateway_tx_id ON payment_gateway_transactions(gateway_transaction_id);

-- 3. Add payment columns to orders table (if not exist)
DO $$ 
BEGIN
    -- payment_status
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'payment_status'
    ) THEN
        ALTER TABLE orders ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'pending' 
            CHECK (payment_status IN ('pending', 'paid', 'held_escrow', 'released', 'failed', 'refunded', 'cancelled'));
    END IF;

    -- payment_method
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'payment_method'
    ) THEN
        ALTER TABLE orders ADD COLUMN payment_method TEXT DEFAULT 'wallet' 
            CHECK (payment_method IN ('wallet', 'click', 'payme', 'uzcard', 'humo', 'visa', 'mastercard', 'cash_on_delivery'));
    END IF;

    -- paid_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'paid_at'
    ) THEN
        ALTER TABLE orders ADD COLUMN paid_at TIMESTAMPTZ;
    END IF;

    -- tracking_number
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'tracking_number'
    ) THEN
        ALTER TABLE orders ADD COLUMN tracking_number TEXT;
    END IF;

    -- carrier
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'carrier'
    ) THEN
        ALTER TABLE orders ADD COLUMN carrier TEXT;
    END IF;

    -- shipped_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'shipped_at'
    ) THEN
        ALTER TABLE orders ADD COLUMN shipped_at TIMESTAMPTZ;
    END IF;

    -- delivered_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'delivered_at'
    ) THEN
        ALTER TABLE orders ADD COLUMN delivered_at TIMESTAMPTZ;
    END IF;

    -- confirmed_by_buyer_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'confirmed_by_buyer_at'
    ) THEN
        ALTER TABLE orders ADD COLUMN confirmed_by_buyer_at TIMESTAMPTZ;
    END IF;

    -- cancelled_at
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'cancelled_at'
    ) THEN
        ALTER TABLE orders ADD COLUMN cancelled_at TIMESTAMPTZ;
    END IF;

    -- cancellation_reason
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'cancellation_reason'
    ) THEN
        ALTER TABLE orders ADD COLUMN cancellation_reason TEXT;
    END IF;
END $$;

-- 4. Order status history (tracking timeline)
CREATE TABLE IF NOT EXISTS order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status TEXT NOT NULL,
    note TEXT,
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_id ON order_status_history(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_history_created_at ON order_status_history(created_at DESC);

-- 5. Wallet transaction ledger (if not exists)
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL,
    balance_after NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'UZS',
    type TEXT NOT NULL CHECK (type IN ('top_up', 'payment', 'refund', 'escrow_hold', 'escrow_release', 'transfer', 'withdrawal', 'commission')),
    reference_type TEXT, -- 'order', 'escrow_hold', 'product', etc.
    reference_id UUID,
    description TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type ON wallet_transactions(type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_reference ON wallet_transactions(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON wallet_transactions(created_at DESC);

-- 6. Security Definer RPC: wallet_payment (atomic payment with escrow)
CREATE OR REPLACE FUNCTION wallet_payment(
    p_buyer_id UUID,
    p_order_id UUID,
    p_amount NUMERIC,
    p_currency TEXT DEFAULT 'UZS',
    p_escrow_days INTEGER DEFAULT 14
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_wallet_balance NUMERIC;
    v_new_balance NUMERIC;
    v_escrow_id UUID;
    v_release_date TIMESTAMPTZ;
BEGIN
    -- 1. Check wallet balance
    SELECT balance INTO v_wallet_balance
    FROM user_wallets
    WHERE user_id = p_buyer_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'wallet_not_found');
    END IF;

    IF v_wallet_balance < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
    END IF;

    -- 2. Debit wallet
    v_new_balance := v_wallet_balance - p_amount;
    
    UPDATE user_wallets
    SET balance = v_new_balance, updated_at = NOW()
    WHERE user_id = p_buyer_id AND currency = p_currency;

    -- 3. Create wallet transaction record
    INSERT INTO wallet_transactions (user_id, amount, balance_after, currency, type, reference_type, reference_id, description)
    VALUES (p_buyer_id, -p_amount, v_new_balance, p_currency, 'payment', 'order', p_order_id, 'Order payment (held in escrow)');

    -- 4. Create escrow hold
    v_release_date := NOW() + (p_escrow_days || ' days')::INTERVAL;
    
    INSERT INTO escrow_holds (order_id, user_id, amount, currency, status, release_at)
    VALUES (p_order_id, p_buyer_id, p_amount, p_currency, 'held', v_release_date)
    RETURNING id INTO v_escrow_id;

    -- 5. Update order payment status
    UPDATE orders
    SET payment_status = 'held_escrow',
        payment_method = 'wallet',
        paid_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 6. Record status history
    INSERT INTO order_status_history (order_id, status, note)
    VALUES (p_order_id, 'paid', 'Payment completed via wallet (escrow hold)');

    RETURN jsonb_build_object(
        'success', true,
        'escrow_id', v_escrow_id,
        'new_balance', v_new_balance,
        'release_at', v_release_date
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 7. Security Definer RPC: release_escrow (pay seller on delivery confirmation)
CREATE OR REPLACE FUNCTION release_escrow(
    p_escrow_id UUID,
    p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_escrow_amount NUMERIC;
    v_escrow_currency TEXT;
    v_seller_id UUID;
    v_seller_balance NUMERIC;
    v_new_seller_balance NUMERIC;
BEGIN
    -- 1. Get escrow details
    SELECT amount, currency INTO v_escrow_amount, v_escrow_currency
    FROM escrow_holds
    WHERE id = p_escrow_id AND status = 'held'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'escrow_not_found_or_already_released');
    END IF;

    -- 2. Get seller from order
    SELECT seller_id INTO v_seller_id
    FROM orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'order_not_found');
    END IF;

    -- 3. Credit seller wallet (create if not exists)
    INSERT INTO user_wallets (user_id, balance, currency)
    VALUES (v_seller_id, v_escrow_amount, v_escrow_currency)
    ON CONFLICT (user_id, currency) DO UPDATE
    SET balance = user_wallets.balance + EXCLUDED.balance,
        updated_at = NOW()
    RETURNING balance INTO v_new_seller_balance;

    -- 4. Record seller wallet transaction
    INSERT INTO wallet_transactions (user_id, amount, balance_after, currency, type, reference_type, reference_id, description)
    VALUES (v_seller_id, v_escrow_amount, v_new_seller_balance, v_escrow_currency, 'escrow_release', 'order', p_order_id, 'Payment received from escrow');

    -- 5. Update escrow status
    UPDATE escrow_holds
    SET status = 'released',
        released_at = NOW(),
        updated_at = NOW()
    WHERE id = p_escrow_id;

    -- 6. Update order payment status
    UPDATE orders
    SET payment_status = 'released',
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 7. Record status history
    INSERT INTO order_status_history (order_id, status, note)
    VALUES (p_order_id, 'completed', 'Escrow released, seller paid');

    RETURN jsonb_build_object(
        'success', true,
        'seller_balance', v_new_seller_balance
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 8. Security Definer RPC: refund_order (cancel + refund to buyer wallet)
CREATE OR REPLACE FUNCTION refund_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_buyer_id UUID;
    v_escrow_id UUID;
    v_escrow_amount NUMERIC;
    v_escrow_currency TEXT;
    v_buyer_balance NUMERIC;
    v_new_buyer_balance NUMERIC;
BEGIN
    -- 1. Get order details
    SELECT buyer_id INTO v_buyer_id
    FROM orders
    WHERE id = p_order_id AND payment_status IN ('held_escrow', 'paid')
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'order_not_found_or_cannot_refund');
    END IF;

    -- 2. Get escrow hold
    SELECT id, amount, currency INTO v_escrow_id, v_escrow_amount, v_escrow_currency
    FROM escrow_holds
    WHERE order_id = p_order_id AND status = 'held'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'escrow_not_found');
    END IF;

    -- 3. Credit buyer wallet (refund)
    SELECT balance INTO v_buyer_balance
    FROM user_wallets
    WHERE user_id = v_buyer_id AND currency = v_escrow_currency
    FOR UPDATE;

    v_new_buyer_balance := COALESCE(v_buyer_balance, 0) + v_escrow_amount;

    INSERT INTO user_wallets (user_id, balance, currency)
    VALUES (v_buyer_id, v_new_buyer_balance, v_escrow_currency)
    ON CONFLICT (user_id, currency) DO UPDATE
    SET balance = user_wallets.balance + v_escrow_amount,
        updated_at = NOW();

    -- 4. Record buyer wallet transaction
    INSERT INTO wallet_transactions (user_id, amount, balance_after, currency, type, reference_type, reference_id, description)
    VALUES (v_buyer_id, v_escrow_amount, v_new_buyer_balance, v_escrow_currency, 'refund', 'order', p_order_id, 'Order refund');

    -- 5. Update escrow status
    UPDATE escrow_holds
    SET status = 'refunded',
        refunded_at = NOW(),
        notes = p_reason,
        updated_at = NOW()
    WHERE id = v_escrow_id;

    -- 6. Update order
    UPDATE orders
    SET status = 'cancelled',
        payment_status = 'refunded',
        cancelled_at = NOW(),
        cancellation_reason = p_reason,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 7. Record status history
    INSERT INTO order_status_history (order_id, status, note)
    VALUES (p_order_id, 'cancelled', CONCAT('Order cancelled and refunded: ', COALESCE(p_reason, 'No reason provided')));

    RETURN jsonb_build_object(
        'success', true,
        'refunded_amount', v_escrow_amount,
        'new_balance', v_new_buyer_balance
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 9. RLS Policies (enable RLS on new tables)
ALTER TABLE escrow_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_gateway_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

-- Escrow holds: users can view their own holds
CREATE POLICY escrow_holds_select ON escrow_holds FOR SELECT
    USING (auth.uid() = user_id);

-- Payment gateway: users can view their own transactions
CREATE POLICY payment_gateway_select ON payment_gateway_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- Order status history: buyers and sellers can view
CREATE POLICY order_status_history_select ON order_status_history FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_status_history.order_id
            AND (orders.buyer_id = auth.uid() OR orders.seller_id = auth.uid())
        )
    );

-- Wallet transactions: users can view their own transactions
CREATE POLICY wallet_transactions_select ON wallet_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- 10. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

-- =========================================================================
-- MIGRATION COMPLETE
-- Tables: escrow_holds, payment_gateway_transactions, order_status_history, wallet_transactions
-- Orders columns: payment_status, payment_method, paid_at, tracking_number, carrier, shipped_at, delivered_at, confirmed_by_buyer_at, cancelled_at, cancellation_reason
-- RPCs: wallet_payment, release_escrow, refund_order
-- =========================================================================
