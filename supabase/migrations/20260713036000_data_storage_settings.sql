BEGIN;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS data_image_quality integer NOT NULL DEFAULT 85,
  ADD COLUMN IF NOT EXISTS auto_download_images_wifi boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS auto_download_images_mobile boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS auto_download_images_roaming boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_videos_wifi boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_videos_mobile boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_videos_roaming boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_files_wifi boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_files_mobile boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_download_files_roaming boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.get_data_storage_settings(p_user_id uuid DEFAULT auth.uid())
RETURNS TABLE (
  data_image_quality integer,
  auto_download_images_wifi boolean,
  auto_download_images_mobile boolean,
  auto_download_images_roaming boolean,
  auto_download_videos_wifi boolean,
  auto_download_videos_mobile boolean,
  auto_download_videos_roaming boolean,
  auto_download_files_wifi boolean,
  auto_download_files_mobile boolean,
  auto_download_files_roaming boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    us.data_image_quality,
    us.auto_download_images_wifi,
    us.auto_download_images_mobile,
    us.auto_download_images_roaming,
    us.auto_download_videos_wifi,
    us.auto_download_videos_mobile,
    us.auto_download_videos_roaming,
    us.auto_download_files_wifi,
    us.auto_download_files_mobile,
    us.auto_download_files_roaming
  FROM public.user_settings us
  WHERE us.user_id = p_user_id
    AND p_user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_data_storage_settings(uuid)
  TO authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
