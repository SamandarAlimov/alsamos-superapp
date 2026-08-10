// Alsamos Global Web Search - Supabase Edge Function
// Proxies web search requests to SearXNG (or fallback providers) with rate limiting and caching

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface SearchRequest {
  query: string
  page?: number
  safeSearch?: 'off' | 'moderate' | 'strict'
  language?: string
  region?: string
}

interface SearchResult {
  title: string
  url: string
  displayUrl: string
  snippet: string
  faviconUrl?: string
  source: string
  publishedDate?: string
}

interface SearchResponse {
  results: SearchResult[]
  page: number
  hasMore: boolean
  totalEstimated?: number
  provider: string
  query: string
}

// Configuration
const SEARXNG_URL = Deno.env.get('SEARXNG_URL') || 'https://searx.be'
const BRAVE_API_KEY = Deno.env.get('BRAVE_API_KEY')
const RATE_LIMIT_PER_MINUTE = 30
const CACHE_TTL_SECONDS = 300 // 5 minutes

serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse request
    const { query, page = 1, safeSearch = 'moderate', language = 'uz', region = 'uz' }: SearchRequest = await req.json()

    // Validate input
    if (!query || query.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: 'Query is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (query.length > 500) {
      return new Response(
        JSON.stringify({ error: 'Query too long (max 500 chars)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get user from auth header
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader! } } }
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Rate limiting check
    const rateLimitKey = `search_rate_${user.id}_${new Date().toISOString().slice(0, 16)}` // per minute
    const { count: recentSearches } = await supabase
      .from('search_history')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('created_at', new Date(Date.now() - 60000).toISOString())

    if (recentSearches && recentSearches >= RATE_LIMIT_PER_MINUTE) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded. Please wait a minute.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check cache
    const cacheKey = `${query.toLowerCase()}_${page}_${safeSearch}_${language}_${region}`
    const { data: cachedResult } = await supabase
      .from('search_cache')
      .select('results, created_at')
      .eq('cache_key', cacheKey)
      .single()

    if (cachedResult && new Date(cachedResult.created_at).getTime() > Date.now() - (CACHE_TTL_SECONDS * 1000)) {
      console.log('Cache hit:', cacheKey)
      return new Response(
        JSON.stringify(cachedResult.results),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Call search provider
    let response: SearchResponse
    try {
      response = await searchViaSearXNG(query, page, safeSearch, language, region)
    } catch (error) {
      console.error('SearXNG failed, trying fallback:', error)
      if (BRAVE_API_KEY) {
        response = await searchViaBrave(query, page, safeSearch, language, region)
      } else {
        throw error
      }
    }

    // Save to search history
    await supabase.from('search_history').insert({
      user_id: user.id,
      query: query.trim(),
      created_at: new Date().toISOString()
    })

    // Cache results
    await supabase.from('search_cache').upsert({
      cache_key: cacheKey,
      results: response,
      created_at: new Date().toISOString()
    }, { onConflict: 'cache_key' })

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Search error:', error)
    return new Response(
      JSON.stringify({ error: 'Search failed. Please try again.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

// SearXNG provider implementation
async function searchViaSearXNG(
  query: string,
  page: number,
  safeSearch: string,
  language: string,
  region: string
): Promise<SearchResponse> {
  const safeSearchMap = { off: 0, moderate: 1, strict: 2 }
  const params = new URLSearchParams({
    q: query,
    format: 'json',
    pageno: page.toString(),
    language: language,
    safesearch: safeSearchMap[safeSearch as keyof typeof safeSearchMap].toString(),
  })

  const response = await fetch(`${SEARXNG_URL}/search?${params}`, {
    headers: { 'Accept': 'application/json' },
    signal: AbortSignal.timeout(10000) // 10s timeout
  })

  if (!response.ok) {
    throw new Error(`SearXNG returned ${response.status}`)
  }

  const data = await response.json()

  return {
    results: (data.results || []).slice(0, 10).map((r: any) => ({
      title: r.title || 'No title',
      url: r.url,
      displayUrl: new URL(r.url).hostname,
      snippet: r.content || r.description || '',
      faviconUrl: `https://www.google.com/s2/favicons?domain=${new URL(r.url).hostname}&sz=32`,
      source: new URL(r.url).hostname,
      publishedDate: r.publishedDate
    })),
    page,
    hasMore: (data.results || []).length >= 10,
    totalEstimated: data.number_of_results,
    provider: 'SearXNG',
    query
  }
}

// Brave Search API fallback
async function searchViaBrave(
  query: string,
  page: number,
  safeSearch: string,
  language: string,
  region: string
): Promise<SearchResponse> {
  const offset = (page - 1) * 10
  const params = new URLSearchParams({
    q: query,
    count: '10',
    offset: offset.toString(),
    safesearch: safeSearch,
    country: region.toUpperCase(),
  })

  const response = await fetch(`https://api.search.brave.com/res/v1/web/search?${params}`, {
    headers: {
      'Accept': 'application/json',
      'X-Subscription-Token': BRAVE_API_KEY!
    },
    signal: AbortSignal.timeout(10000)
  })

  if (!response.ok) {
    throw new Error(`Brave API returned ${response.status}`)
  }

  const data = await response.json()

  return {
    results: (data.web?.results || []).map((r: any) => ({
      title: r.title,
      url: r.url,
      displayUrl: new URL(r.url).hostname,
      snippet: r.description,
      faviconUrl: r.profile?.img || `https://www.google.com/s2/favicons?domain=${new URL(r.url).hostname}&sz=32`,
      source: new URL(r.url).hostname,
      publishedDate: r.age
    })),
    page,
    hasMore: (data.web?.results || []).length >= 10,
    totalEstimated: data.web?.results?.length,
    provider: 'Brave Search',
    query
  }
}
