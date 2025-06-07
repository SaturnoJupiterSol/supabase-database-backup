

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."conversion_type" AS ENUM (
    'form_submission',
    'sale',
    'lead',
    'signup'
);


ALTER TYPE "public"."conversion_type" OWNER TO "postgres";


CREATE TYPE "public"."lead_status" AS ENUM (
    'new',
    'contacted',
    'qualified',
    'converted',
    'lost'
);


ALTER TYPE "public"."lead_status" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'admin',
    'user'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_register_lead_conversion"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Registrar conversão se houver metadata de visitor_id
  IF NEW.form_metadata ? 'visitor_id' THEN
    PERFORM public.register_conversion(
      NEW.form_id,
      NEW.id,
      NEW.form_metadata->>'visitor_id',
      'lead'::conversion_type,
      0
    );
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_register_lead_conversion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_public_lead"("p_form_id" "uuid", "p_user_id" "uuid", "p_name" "text", "p_email" "text", "p_phone" "text" DEFAULT NULL::"text", "p_message" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT 'new'::"text", "p_source" "text" DEFAULT 'form'::"text", "p_form_metadata" "jsonb" DEFAULT '{}'::"jsonb", "p_attachments" "jsonb" DEFAULT '[]'::"jsonb") RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Inserir o lead na tabela leads
  RETURN QUERY
  INSERT INTO public.leads (
    form_id,
    user_id,
    name,
    email,
    phone,
    message,
    status,
    source,
    form_metadata,
    attachments
  ) VALUES (
    p_form_id,
    p_user_id,
    p_name,
    p_email,
    p_phone,
    p_message,
    p_status::lead_status,
    p_source,
    p_form_metadata,
    p_attachments
  )
  RETURNING leads.id, leads.created_at;
END;
$$;


ALTER FUNCTION "public"."create_public_lead"("p_form_id" "uuid", "p_user_id" "uuid", "p_name" "text", "p_email" "text", "p_phone" "text", "p_message" "text", "p_status" "text", "p_source" "text", "p_form_metadata" "jsonb", "p_attachments" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_cloaking_slug"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Se link cloaking foi habilitado e não há slug ainda
  IF NEW.enable_link_cloaking = true AND (OLD.enable_link_cloaking = false OR OLD.enable_link_cloaking IS NULL OR NEW.cloaking_slug IS NULL) THEN
    -- Gerar slug único baseado no nome do link + timestamp
    NEW.cloaking_slug := lower(regexp_replace(NEW.name, '[^a-zA-Z0-9]', '-', 'g')) || '-' || extract(epoch from now())::text;
    
    -- Garantir que o slug é único
    WHILE EXISTS (SELECT 1 FROM tracking_links WHERE cloaking_slug = NEW.cloaking_slug AND id != NEW.id) LOOP
      NEW.cloaking_slug := NEW.cloaking_slug || '-' || floor(random() * 1000)::text;
    END LOOP;
  END IF;
  
  -- Se link cloaking foi desabilitado, remover o slug
  IF NEW.enable_link_cloaking = false THEN
    NEW.cloaking_slug := NULL;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_cloaking_slug"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.email)
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"("user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = user_id AND role = 'admin' AND is_active = true
  );
$$;


ALTER FUNCTION "public"."is_admin"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_conversion"("p_form_id" "uuid", "p_lead_id" "uuid", "p_visitor_id" "text" DEFAULT NULL::"text", "p_conversion_type" "public"."conversion_type" DEFAULT 'form_submission'::"public"."conversion_type", "p_value" numeric DEFAULT 0) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_link_id uuid;
  v_conversion_id uuid;
  v_user_id uuid;
BEGIN
  -- Buscar o link_id mais recente baseado no visitor_id
  IF p_visitor_id IS NOT NULL THEN
    SELECT link_id INTO v_link_id
    FROM public.link_clicks
    WHERE visitor_id = p_visitor_id
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- Buscar user_id do formulário ou lead
  IF p_form_id IS NOT NULL THEN
    SELECT user_id INTO v_user_id FROM public.forms WHERE id = p_form_id;
  ELSIF p_lead_id IS NOT NULL THEN
    SELECT user_id INTO v_user_id FROM public.leads WHERE id = p_lead_id;
  END IF;

  -- Inserir evento de conversão
  INSERT INTO public.conversion_events (
    link_id,
    user_id,
    form_id,
    lead_id,
    type,
    value
  ) VALUES (
    v_link_id,
    v_user_id,
    p_form_id,
    p_lead_id,
    p_conversion_type,
    p_value
  )
  RETURNING id INTO v_conversion_id;

  RETURN v_conversion_id;
END;
$$;


ALTER FUNCTION "public"."register_conversion"("p_form_id" "uuid", "p_lead_id" "uuid", "p_visitor_id" "text", "p_conversion_type" "public"."conversion_type", "p_value" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."conversion_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "link_id" "uuid",
    "user_id" "uuid",
    "form_id" "uuid",
    "lead_id" "uuid",
    "type" "public"."conversion_type" NOT NULL,
    "value" numeric(10,2) DEFAULT 0,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."conversion_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."features_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "feature_name" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."features_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."form_submissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "form_id" "uuid" NOT NULL,
    "form_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ip_address" "inet",
    "user_agent" "text"
);


ALTER TABLE "public"."form_submissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fields" "jsonb" DEFAULT '[]'::"jsonb",
    "steps" "jsonb" DEFAULT '[]'::"jsonb",
    "enable_steps" boolean DEFAULT false,
    "final_step" "jsonb",
    "color_theme" "jsonb" DEFAULT '{"accent": "#ec4899", "primary": "#3b82f6", "secondary": "#8b5cf6"}'::"jsonb",
    "display_config" "jsonb"
);


ALTER TABLE "public"."forms" OWNER TO "postgres";


COMMENT ON COLUMN "public"."forms"."steps" IS 'Array de etapas do formulário com campos e configurações';



COMMENT ON COLUMN "public"."forms"."enable_steps" IS 'Ativar ou desativar função de formulário multi-step';



COMMENT ON COLUMN "public"."forms"."color_theme" IS 'Tema de cores personalizado do formulário com primary, secondary e accent';



CREATE TABLE IF NOT EXISTS "public"."geo_routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "link_id" "uuid" NOT NULL,
    "geo_type" "text" NOT NULL,
    "geo_code" "text" NOT NULL,
    "target_url" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "geo_routes_geo_type_check" CHECK (("geo_type" = ANY (ARRAY['country'::"text", 'state'::"text", 'city'::"text"])))
);


ALTER TABLE "public"."geo_routes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."google_integration_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "target_type" "text" NOT NULL,
    "target_value" "text" NOT NULL,
    "script_type" "text" NOT NULL,
    "script_content" "text",
    "trigger_event" "text",
    "priority" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "google_integration_rules_script_type_check" CHECK (("script_type" = ANY (ARRAY['analytics'::"text", 'ads'::"text", 'tag_manager'::"text", 'custom'::"text"]))),
    CONSTRAINT "google_integration_rules_target_type_check" CHECK (("target_type" = ANY (ARRAY['page'::"text", 'form'::"text", 'button'::"text", 'url_pattern'::"text", 'element_selector'::"text"]))),
    CONSTRAINT "google_integration_rules_trigger_event_check" CHECK (("trigger_event" = ANY (ARRAY['page_load'::"text", 'form_submit'::"text", 'button_click'::"text", 'custom_event'::"text"])))
);


ALTER TABLE "public"."google_integration_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "form_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "phone" "text",
    "message" "text",
    "status" "public"."lead_status" DEFAULT 'new'::"public"."lead_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'form'::"text",
    "form_metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb",
    "assigned_to" "text",
    "notes" "text",
    CONSTRAINT "leads_source_check" CHECK (("source" = ANY (ARRAY['form'::"text", 'manual'::"text", 'import'::"text", 'referral'::"text", 'social'::"text", 'advertising'::"text", 'website'::"text", 'landing_page'::"text", 'email'::"text", 'phone'::"text", 'chat'::"text"])))
);


ALTER TABLE "public"."leads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."link_clicks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "link_id" "uuid",
    "visitor_id" "text",
    "ip_address" "inet",
    "user_agent" "text",
    "referrer" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "country" "text",
    "city" "text",
    "browser" "text",
    "os" "text",
    "device_type" "text"
);


ALTER TABLE "public"."link_clicks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "type" "text" NOT NULL,
    "read" boolean DEFAULT false NOT NULL,
    "action_url" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['info'::"text", 'success'::"text", 'warning'::"text", 'error'::"text"])))
);

ALTER TABLE ONLY "public"."notifications" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."page_views" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "page_type" "text" NOT NULL,
    "page_id" "uuid",
    "user_id" "uuid",
    "visitor_id" "text",
    "ip_address" "inet",
    "user_agent" "text",
    "referrer" "text",
    "country" "text",
    "city" "text",
    "browser" "text",
    "os" "text",
    "device_type" "text",
    "session_id" "text",
    "duration_seconds" integer DEFAULT 0,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."page_views" REPLICA IDENTITY FULL;


ALTER TABLE "public"."page_views" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "name" "text",
    "role" "public"."user_role" DEFAULT 'user'::"public"."user_role" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_name" "text",
    "timezone" "text" DEFAULT 'America/Sao_Paulo'::"text",
    "email_notifications" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "google_analytics_id" "text",
    "google_analytics_enabled" boolean DEFAULT false,
    "google_ads_id" "text",
    "google_tag_manager_id" "text",
    "google_tag_manager_enabled" boolean DEFAULT false,
    "google_analytics_pages" "jsonb" DEFAULT '["*"]'::"jsonb",
    "company_logo_url" "text",
    "show_logo_in_forms" boolean DEFAULT true,
    "show_logo_in_auth" boolean DEFAULT true
);


ALTER TABLE "public"."system_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."system_settings"."company_logo_url" IS 'URL do logo da empresa';



COMMENT ON COLUMN "public"."system_settings"."show_logo_in_forms" IS 'Mostrar logo nos formulários públicos';



COMMENT ON COLUMN "public"."system_settings"."show_logo_in_auth" IS 'Mostrar logo nas telas de autenticação';



CREATE TABLE IF NOT EXISTS "public"."tracking_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "url" "text" NOT NULL,
    "campaign_source" "text",
    "campaign_medium" "text",
    "campaign_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "enable_geo_redirect" boolean DEFAULT false NOT NULL,
    "enable_link_cloaking" boolean DEFAULT false NOT NULL,
    "cloaking_slug" "text",
    "tracking_mode" "text" DEFAULT 'both'::"text" NOT NULL,
    "conversion_trigger" "text" DEFAULT 'final_screen'::"text" NOT NULL,
    CONSTRAINT "conversion_trigger_check" CHECK (("conversion_trigger" = ANY (ARRAY['button_click'::"text", 'final_screen'::"text"]))),
    CONSTRAINT "tracking_links_tracking_mode_check" CHECK (("tracking_mode" = ANY (ARRAY['view'::"text", 'click'::"text", 'both'::"text"])))
);


ALTER TABLE "public"."tracking_links" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tracking_links"."tracking_mode" IS 'Tipo de rastreamento: view (apenas visualizações), click (apenas cliques), both (ambos)';



COMMENT ON COLUMN "public"."tracking_links"."conversion_trigger" IS 'Tipo de gatilho para conversão: button_click ou final_screen';



CREATE TABLE IF NOT EXISTS "public"."visitor_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "link_id" "uuid",
    "ip_address" "inet",
    "device_id" "text" NOT NULL,
    "user_agent" "text",
    "total_visits" integer DEFAULT 1 NOT NULL,
    "first_visit_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_visit_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."visitor_sessions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."conversion_events"
    ADD CONSTRAINT "conversion_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."features_config"
    ADD CONSTRAINT "features_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."features_config"
    ADD CONSTRAINT "features_config_user_id_feature_name_key" UNIQUE ("user_id", "feature_name");



ALTER TABLE ONLY "public"."form_submissions"
    ADD CONSTRAINT "form_submissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forms"
    ADD CONSTRAINT "forms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."geo_routes"
    ADD CONSTRAINT "geo_routes_link_id_geo_type_geo_code_key" UNIQUE ("link_id", "geo_type", "geo_code");



ALTER TABLE ONLY "public"."geo_routes"
    ADD CONSTRAINT "geo_routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."google_integration_rules"
    ADD CONSTRAINT "google_integration_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."link_clicks"
    ADD CONSTRAINT "link_clicks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."page_views"
    ADD CONSTRAINT "page_views_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."tracking_links"
    ADD CONSTRAINT "tracking_links_cloaking_slug_key" UNIQUE ("cloaking_slug");



ALTER TABLE ONLY "public"."tracking_links"
    ADD CONSTRAINT "tracking_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."visitor_sessions"
    ADD CONSTRAINT "visitor_sessions_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_conversion_events_created_at" ON "public"."conversion_events" USING "btree" ("created_at");



CREATE INDEX "idx_conversion_events_link_id" ON "public"."conversion_events" USING "btree" ("link_id");



CREATE INDEX "idx_form_submissions_form_id" ON "public"."form_submissions" USING "btree" ("form_id");



CREATE INDEX "idx_form_submissions_submitted_at" ON "public"."form_submissions" USING "btree" ("submitted_at");



CREATE INDEX "idx_forms_user_id" ON "public"."forms" USING "btree" ("user_id");



CREATE INDEX "idx_geo_routes_active" ON "public"."geo_routes" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_geo_routes_geo_type_code" ON "public"."geo_routes" USING "btree" ("geo_type", "geo_code");



CREATE INDEX "idx_geo_routes_link_id" ON "public"."geo_routes" USING "btree" ("link_id");



CREATE INDEX "idx_leads_created_at" ON "public"."leads" USING "btree" ("created_at");



CREATE INDEX "idx_leads_form_id" ON "public"."leads" USING "btree" ("form_id");



CREATE INDEX "idx_leads_status" ON "public"."leads" USING "btree" ("status");



CREATE INDEX "idx_leads_user_id" ON "public"."leads" USING "btree" ("user_id");



CREATE INDEX "idx_link_clicks_browser" ON "public"."link_clicks" USING "btree" ("browser");



CREATE INDEX "idx_link_clicks_city" ON "public"."link_clicks" USING "btree" ("city");



CREATE INDEX "idx_link_clicks_country" ON "public"."link_clicks" USING "btree" ("country");



CREATE INDEX "idx_link_clicks_created_at" ON "public"."link_clicks" USING "btree" ("created_at");



CREATE INDEX "idx_link_clicks_device_type" ON "public"."link_clicks" USING "btree" ("device_type");



CREATE INDEX "idx_link_clicks_link_id" ON "public"."link_clicks" USING "btree" ("link_id");



CREATE INDEX "idx_link_clicks_visitor_id" ON "public"."link_clicks" USING "btree" ("visitor_id");



CREATE INDEX "idx_notifications_created_at" ON "public"."notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_notifications_read" ON "public"."notifications" USING "btree" ("read");



CREATE INDEX "idx_notifications_user_id" ON "public"."notifications" USING "btree" ("user_id");



CREATE INDEX "idx_page_views_created_at" ON "public"."page_views" USING "btree" ("created_at");



CREATE INDEX "idx_page_views_page_id" ON "public"."page_views" USING "btree" ("page_id");



CREATE INDEX "idx_page_views_page_type" ON "public"."page_views" USING "btree" ("page_type");



CREATE INDEX "idx_page_views_user_id" ON "public"."page_views" USING "btree" ("user_id");



CREATE INDEX "idx_page_views_visitor_id" ON "public"."page_views" USING "btree" ("visitor_id");



CREATE INDEX "idx_tracking_links_cloaking_slug" ON "public"."tracking_links" USING "btree" ("cloaking_slug") WHERE ("cloaking_slug" IS NOT NULL);



CREATE INDEX "idx_visitor_sessions_device_id" ON "public"."visitor_sessions" USING "btree" ("device_id");



CREATE INDEX "idx_visitor_sessions_ip_device" ON "public"."visitor_sessions" USING "btree" ("ip_address", "device_id");



CREATE INDEX "idx_visitor_sessions_link_id" ON "public"."visitor_sessions" USING "btree" ("link_id");



CREATE UNIQUE INDEX "idx_visitor_sessions_unique" ON "public"."visitor_sessions" USING "btree" ("link_id", "ip_address", "device_id");



CREATE OR REPLACE TRIGGER "trigger_auto_register_lead_conversion" AFTER INSERT ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."auto_register_lead_conversion"();



CREATE OR REPLACE TRIGGER "trigger_generate_cloaking_slug" BEFORE UPDATE ON "public"."tracking_links" FOR EACH ROW EXECUTE FUNCTION "public"."generate_cloaking_slug"();



CREATE OR REPLACE TRIGGER "update_features_config_updated_at" BEFORE UPDATE ON "public"."features_config" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_forms_updated_at" BEFORE UPDATE ON "public"."forms" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_geo_routes_updated_at" BEFORE UPDATE ON "public"."geo_routes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_google_integration_rules_updated_at" BEFORE UPDATE ON "public"."google_integration_rules" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_leads_updated_at" BEFORE UPDATE ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_system_settings_updated_at" BEFORE UPDATE ON "public"."system_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_visitor_sessions_updated_at" BEFORE UPDATE ON "public"."visitor_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."conversion_events"
    ADD CONSTRAINT "conversion_events_form_id_fkey" FOREIGN KEY ("form_id") REFERENCES "public"."forms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversion_events"
    ADD CONSTRAINT "conversion_events_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."leads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversion_events"
    ADD CONSTRAINT "conversion_events_link_id_fkey" FOREIGN KEY ("link_id") REFERENCES "public"."tracking_links"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversion_events"
    ADD CONSTRAINT "conversion_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."features_config"
    ADD CONSTRAINT "features_config_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."form_submissions"
    ADD CONSTRAINT "form_submissions_form_id_fkey" FOREIGN KEY ("form_id") REFERENCES "public"."forms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."forms"
    ADD CONSTRAINT "forms_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."google_integration_rules"
    ADD CONSTRAINT "google_integration_rules_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_form_id_fkey" FOREIGN KEY ("form_id") REFERENCES "public"."forms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."link_clicks"
    ADD CONSTRAINT "link_clicks_link_id_fkey" FOREIGN KEY ("link_id") REFERENCES "public"."tracking_links"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."tracking_links"
    ADD CONSTRAINT "tracking_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."visitor_sessions"
    ADD CONSTRAINT "visitor_sessions_link_id_fkey" FOREIGN KEY ("link_id") REFERENCES "public"."tracking_links"("id") ON DELETE CASCADE;



CREATE POLICY "Admins can update all profiles" ON "public"."profiles" FOR UPDATE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "Admins can view all profiles" ON "public"."profiles" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "Allow anonymous users to create leads from public forms" ON "public"."leads" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow inserting notifications" ON "public"."notifications" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow public access to forms" ON "public"."forms" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Allow public form submissions" ON "public"."leads" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."forms"
  WHERE (("forms"."id" = "leads"."form_id") AND ("forms"."user_id" = "leads"."user_id")))));



CREATE POLICY "Allow public insert on page_views" ON "public"."page_views" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow public read access to forms" ON "public"."forms" FOR SELECT USING (true);



CREATE POLICY "Allow public to insert link clicks" ON "public"."link_clicks" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow system to insert conversion events" ON "public"."conversion_events" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can insert visitor sessions" ON "public"."visitor_sessions" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can read forms for public access" ON "public"."forms" FOR SELECT USING (true);



CREATE POLICY "Anyone can submit forms" ON "public"."form_submissions" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can update visitor sessions" ON "public"."visitor_sessions" FOR UPDATE USING (true);



CREATE POLICY "Form owners can view submissions" ON "public"."form_submissions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."forms"
  WHERE (("forms"."id" = "form_submissions"."form_id") AND ("forms"."user_id" = "auth"."uid"())))));



CREATE POLICY "Public can view form structure" ON "public"."forms" FOR SELECT USING (true);



CREATE POLICY "Public can view forms for public access" ON "public"."forms" FOR SELECT USING (true);



CREATE POLICY "Users can create forms" ON "public"."forms" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create geo routes for their own links" ON "public"."geo_routes" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "geo_routes"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create leads" ON "public"."leads" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create leads for their forms" ON "public"."leads" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") AND (EXISTS ( SELECT 1
   FROM "public"."forms"
  WHERE (("forms"."id" = "leads"."form_id") AND ("forms"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can create their own feature configs" ON "public"."features_config" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own forms" ON "public"."forms" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own integration rules" ON "public"."google_integration_rules" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own settings" ON "public"."system_settings" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own tracking links" ON "public"."tracking_links" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own forms" ON "public"."forms" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own geo routes" ON "public"."geo_routes" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "geo_routes"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete their own integration rules" ON "public"."google_integration_rules" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own leads" ON "public"."leads" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own tracking links" ON "public"."tracking_links" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert leads for their forms" ON "public"."leads" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."forms"
  WHERE (("forms"."id" = "leads"."form_id") AND ("forms"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert their own forms" ON "public"."forms" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own leads" ON "public"."leads" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own forms" ON "public"."forms" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own feature configs" ON "public"."features_config" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own forms" ON "public"."forms" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own geo routes" ON "public"."geo_routes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "geo_routes"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update their own integration rules" ON "public"."google_integration_rules" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own leads" ON "public"."leads" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own notifications" ON "public"."notifications" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own settings" ON "public"."system_settings" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own tracking links" ON "public"."tracking_links" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view clicks on their links" ON "public"."link_clicks" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "link_clicks"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view conversions from their links" ON "public"."conversion_events" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "conversion_events"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))) OR ("auth"."uid"() = "user_id")));



CREATE POLICY "Users can view sessions of their own links" ON "public"."visitor_sessions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "visitor_sessions"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view their own feature configs" ON "public"."features_config" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own forms" ON "public"."forms" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own geo routes" ON "public"."geo_routes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tracking_links"
  WHERE (("tracking_links"."id" = "geo_routes"."link_id") AND ("tracking_links"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view their own integration rules" ON "public"."google_integration_rules" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own leads" ON "public"."leads" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own notifications" ON "public"."notifications" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own page views" ON "public"."page_views" FOR SELECT USING ((("auth"."uid"() = "user_id") OR ("user_id" IS NULL)));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view their own settings" ON "public"."system_settings" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own tracking links" ON "public"."tracking_links" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."conversion_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."features_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."form_submissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."forms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."geo_routes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."google_integration_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."link_clicks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."page_views" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tracking_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."visitor_sessions" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."page_views";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."auto_register_lead_conversion"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_register_lead_conversion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_register_lead_conversion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_public_lead"("p_form_id" "uuid", "p_user_id" "uuid", "p_name" "text", "p_email" "text", "p_phone" "text", "p_message" "text", "p_status" "text", "p_source" "text", "p_form_metadata" "jsonb", "p_attachments" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_public_lead"("p_form_id" "uuid", "p_user_id" "uuid", "p_name" "text", "p_email" "text", "p_phone" "text", "p_message" "text", "p_status" "text", "p_source" "text", "p_form_metadata" "jsonb", "p_attachments" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_public_lead"("p_form_id" "uuid", "p_user_id" "uuid", "p_name" "text", "p_email" "text", "p_phone" "text", "p_message" "text", "p_status" "text", "p_source" "text", "p_form_metadata" "jsonb", "p_attachments" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_cloaking_slug"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_cloaking_slug"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_cloaking_slug"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."register_conversion"("p_form_id" "uuid", "p_lead_id" "uuid", "p_visitor_id" "text", "p_conversion_type" "public"."conversion_type", "p_value" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."register_conversion"("p_form_id" "uuid", "p_lead_id" "uuid", "p_visitor_id" "text", "p_conversion_type" "public"."conversion_type", "p_value" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_conversion"("p_form_id" "uuid", "p_lead_id" "uuid", "p_visitor_id" "text", "p_conversion_type" "public"."conversion_type", "p_value" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."conversion_events" TO "anon";
GRANT ALL ON TABLE "public"."conversion_events" TO "authenticated";
GRANT ALL ON TABLE "public"."conversion_events" TO "service_role";



GRANT ALL ON TABLE "public"."features_config" TO "anon";
GRANT ALL ON TABLE "public"."features_config" TO "authenticated";
GRANT ALL ON TABLE "public"."features_config" TO "service_role";



GRANT ALL ON TABLE "public"."form_submissions" TO "anon";
GRANT ALL ON TABLE "public"."form_submissions" TO "authenticated";
GRANT ALL ON TABLE "public"."form_submissions" TO "service_role";



GRANT ALL ON TABLE "public"."forms" TO "anon";
GRANT ALL ON TABLE "public"."forms" TO "authenticated";
GRANT ALL ON TABLE "public"."forms" TO "service_role";



GRANT ALL ON TABLE "public"."geo_routes" TO "anon";
GRANT ALL ON TABLE "public"."geo_routes" TO "authenticated";
GRANT ALL ON TABLE "public"."geo_routes" TO "service_role";



GRANT ALL ON TABLE "public"."google_integration_rules" TO "anon";
GRANT ALL ON TABLE "public"."google_integration_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."google_integration_rules" TO "service_role";



GRANT ALL ON TABLE "public"."leads" TO "anon";
GRANT ALL ON TABLE "public"."leads" TO "authenticated";
GRANT ALL ON TABLE "public"."leads" TO "service_role";



GRANT ALL ON TABLE "public"."link_clicks" TO "anon";
GRANT ALL ON TABLE "public"."link_clicks" TO "authenticated";
GRANT ALL ON TABLE "public"."link_clicks" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."page_views" TO "anon";
GRANT ALL ON TABLE "public"."page_views" TO "authenticated";
GRANT ALL ON TABLE "public"."page_views" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."system_settings" TO "anon";
GRANT ALL ON TABLE "public"."system_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."system_settings" TO "service_role";



GRANT ALL ON TABLE "public"."tracking_links" TO "anon";
GRANT ALL ON TABLE "public"."tracking_links" TO "authenticated";
GRANT ALL ON TABLE "public"."tracking_links" TO "service_role";



GRANT ALL ON TABLE "public"."visitor_sessions" TO "anon";
GRANT ALL ON TABLE "public"."visitor_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."visitor_sessions" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
