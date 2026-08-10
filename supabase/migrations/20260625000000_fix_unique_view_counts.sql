-- Function to get unique viewer counts for multiple posts
CREATE OR REPLACE FUNCTION public.get_unique_view_counts(post_ids uuid[])
RETURNS TABLE(post_id uuid, count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pv.post_id,
    COUNT(DISTINCT pv.user_id) as count
  FROM public.post_views pv
  WHERE pv.post_id = ANY(post_ids)
  GROUP BY pv.post_id;
END;
$$;

-- Update the sync function to count distinct users
CREATE OR REPLACE FUNCTION public.sync_post_views_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  unique_count integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Count distinct users for this post
    SELECT COUNT(DISTINCT user_id) INTO unique_count
    FROM public.post_views
    WHERE post_id = NEW.post_id;
    
    UPDATE public.posts 
    SET views_count = unique_count 
    WHERE id = NEW.post_id;
    
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    -- Recalculate distinct users for this post
    SELECT COUNT(DISTINCT user_id) INTO unique_count
    FROM public.post_views
    WHERE post_id = OLD.post_id;
    
    UPDATE public.posts 
    SET views_count = unique_count 
    WHERE id = OLD.post_id;
    
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Recalculate distinct users for this post
    SELECT COUNT(DISTINCT user_id) INTO unique_count
    FROM public.post_views
    WHERE post_id = NEW.post_id;
    
    UPDATE public.posts 
    SET views_count = unique_count 
    WHERE id = NEW.post_id;
    
    RETURN NEW;
  END IF;
  
  RETURN NULL;
END;
$$;

-- Recreate the trigger
DROP TRIGGER IF EXISTS sync_post_views_count_trigger ON public.post_views;
CREATE TRIGGER sync_post_views_count_trigger
AFTER INSERT OR DELETE OR UPDATE ON public.post_views
FOR EACH ROW EXECUTE FUNCTION public.sync_post_views_count();

-- Fix all existing view counts to be accurate (count distinct users)
UPDATE public.posts p
SET views_count = (
  SELECT COUNT(DISTINCT user_id)
  FROM public.post_views pv
  WHERE pv.post_id = p.id
);
