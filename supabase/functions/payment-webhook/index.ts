// Payment gateway webhook handler
// Handles callbacks from Click, Payme, Uzcard, and card payment providers
// Updates order and payment status in database

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { createHash } from 'node:crypto'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WebhookPayload {
  provider: 'click' | 'payme' | 'uzcard' | 'card'
  orderId: string
  transactionId: string
  amount: number
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled'
  signature?: string
  metadata?: Record<string, any>
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const payload: WebhookPayload = await req.json()
    const { provider, orderId, transactionId, amount, status, signature, metadata } = payload

    console.log('Payment webhook received:', { provider, orderId, status })

    // Verify signature (provider-specific)
    const isValid = await verifySignature(provider, payload, signature, req)
    if (!isValid) {
      console.error('Invalid webhook signature')
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Update payment gateway transaction
    const { error: txError } = await supabaseClient
      .from('payment_gateway_transactions')
      .update({
        status,
        gateway_transaction_id: transactionId,
        callback_data: metadata,
        completed_at: status === 'completed' ? new Date().toISOString() : null,
        failed_at: status === 'failed' ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      })
      .eq('order_id', orderId)
      .eq('gateway', provider)

    if (txError) {
      console.error('Failed to update payment transaction:', txError)
      throw txError
    }

    // If payment completed, update order status and create escrow hold
    if (status === 'completed') {
      // Get order details
      const { data: order, error: orderError } = await supabaseClient
        .from('orders')
        .select('buyer_id, total, currency')
        .eq('id', orderId)
        .single()

      if (orderError || !order) {
        console.error('Order not found:', orderError)
        throw new Error('Order not found')
      }

      // Update order payment status
      const { error: updateError } = await supabaseClient
        .from('orders')
        .update({
          payment_status: 'held_escrow',
          payment_method: provider,
          paid_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', orderId)

      if (updateError) {
        console.error('Failed to update order:', updateError)
        throw updateError
      }

      // Create escrow hold (14 days)
      const releaseAt = new Date()
      releaseAt.setDate(releaseAt.getDate() + 14)

      const { error: escrowError } = await supabaseClient
        .from('escrow_holds')
        .insert({
          order_id: orderId,
          user_id: order.buyer_id,
          amount: order.total,
          currency: order.currency || 'UZS',
          status: 'held',
          release_at: releaseAt.toISOString(),
        })

      if (escrowError) {
        console.error('Failed to create escrow hold:', escrowError)
        throw escrowError
      }

      // Record status history
      await supabaseClient.from('order_status_history').insert({
        order_id: orderId,
        status: 'paid',
        note: `Payment completed via ${provider} (escrow hold)`,
      })

      console.log('Payment completed, escrow created for order:', orderId)
    }

    // If payment failed, update order status
    if (status === 'failed' || status === 'cancelled') {
      await supabaseClient
        .from('orders')
        .update({
          payment_status: status === 'failed' ? 'failed' : 'cancelled',
          updated_at: new Date().toISOString(),
        })
        .eq('id', orderId)

      await supabaseClient.from('order_status_history').insert({
        order_id: orderId,
        status: 'cancelled',
        note: `Payment ${status} via ${provider}`,
      })

      console.log(`Payment ${status} for order:`, orderId)
    }

    return new Response(
      JSON.stringify({ success: true, orderId, status }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

// Provider-specific signature verification
async function verifySignature(
  provider: string,
  payload: WebhookPayload,
  signature?: string,
  req?: Request,
): Promise<boolean> {
  switch (provider) {
    case 'click':
      return verifyClickSignature(payload, signature)

    case 'payme':
      return verifyPaymeAuth(req)

    case 'uzcard':
      // Uzcard signature verification (implement when credentials available)
      return true

    case 'card':
      // Card payment aggregator signature (implement when credentials available)
      return true

    default:
      return false
  }
}

// Click (Uzbekistan) webhook signature verification
// Signature = MD5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + amount + action + sign_time)
function verifyClickSignature(payload: WebhookPayload, signature?: string): boolean {
  if (!signature) return false

  const secretKey = Deno.env.get('CLICK_SECRET_KEY')
  if (!secretKey) {
    console.error('CLICK_SECRET_KEY not configured')
    return false
  }

  const { metadata } = payload
  if (!metadata) return false

  const {
    click_trans_id,
    service_id,
    merchant_trans_id,
    amount,
    action,
    sign_time,
    merchant_prepare_id,
  } = metadata

  // Build sign string based on action (0=prepare, 1=complete)
  let signString: string
  if (action === 0 || action === '0') {
    // Prepare: click_trans_id + service_id + secret_key + merchant_trans_id + amount + action + sign_time
    signString = `${click_trans_id}${service_id}${secretKey}${merchant_trans_id}${amount}${action}${sign_time}`
  } else if (action === 1 || action === '1') {
    // Complete: click_trans_id + service_id + secret_key + merchant_trans_id + merchant_prepare_id + amount + action + sign_time
    signString = `${click_trans_id}${service_id}${secretKey}${merchant_trans_id}${merchant_prepare_id}${amount}${action}${sign_time}`
  } else {
    console.error('Invalid Click action:', action)
    return false
  }

  // Calculate MD5 hash
  const hash = createHash('md5').update(signString).digest('hex')
  
  const isValid = hash === signature
  if (!isValid) {
    console.error('Click signature mismatch:', { expected: hash, received: signature })
  }

  return isValid
}

// Payme (Paycom) webhook authentication
// Uses HTTP Basic Auth: "Paycom:PAYME_KEY"
function verifyPaymeAuth(req?: Request): boolean {
  if (!req) return false

  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !authHeader.startsWith('Basic ')) {
    console.error('Payme: Missing or invalid Authorization header')
    return false
  }

  const paymeKey = Deno.env.get('PAYME_KEY')
  if (!paymeKey) {
    console.error('PAYME_KEY not configured')
    return false
  }

  // Decode base64
  const base64Credentials = authHeader.slice(6) // Remove "Basic "
  const credentials = atob(base64Credentials)
  const [login, password] = credentials.split(':')

  const isValid = login === 'Paycom' && password === paymeKey
  if (!isValid) {
    console.error('Payme auth failed:', { login, keyMatch: password === paymeKey })
  }

  return isValid
}
