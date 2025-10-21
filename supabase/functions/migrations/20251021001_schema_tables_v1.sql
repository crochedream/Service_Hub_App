-- Cleaning Service Database Schema cleaning_service_hub
CREATE SCHEMA IF NOT EXISTS public;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA public;

-- User Roles Enum
CREATE TYPE public.user_role AS ENUM (
  'app_admin',
  'service_admin',
  'branch_admin',
  'cleaner',
  'customer'
);

-- Service Status Enum (for franchise approval)
CREATE TYPE public.service_status AS ENUM (
  'pending_approval',
  'approved',
  'rejected',
  'suspended'
);

-- Branch Status Enum (for individual branch operations)
CREATE TYPE public.branch_status AS ENUM (
  'active',
  'inactive',
  'temporarily_closed',
  'under_maintenance'
);

-- Cleaner Status Enum
CREATE TYPE public.cleaner_status AS ENUM (
  'active',
  'inactive',
  'on_leave',
  'terminated'
);

-- =============================================
-- PROFILES TABLE (extends Supabase auth.users)
-- =============================================
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role user_role NOT NULL,
  --full_name TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  date_of_birth DATE,
  gender TEXT CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),
  avatar_url TEXT, -- Will store Supabase storage URL
  address_line TEXT,
  city TEXT,
  state TEXT,
  postal_code TEXT,
  country TEXT DEFAULT 'Malaysia',
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================
-- CLEANING SERVICES TABLE (Franchises)
-- =============================================
CREATE TABLE public.cleaning_services (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_name TEXT NOT NULL,
  business_license TEXT,
  business_address TEXT NOT NULL,
  logo_url TEXT,
  description TEXT,
  phone TEXT NOT NULL,
  email TEXT NOT NULL,
  status public.service_status DEFAULT 'pending_approval',
  approved_by UUID REFERENCES profiles(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID NOT NULL REFERENCES profiles(id), -- First service admin who created it
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================
-- SERVICE ADMINS TABLE (Multiple admins per service)
-- =============================================
CREATE TABLE public.service_admins (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES public.cleaning_services(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_primary BOOLEAN DEFAULT false, -- Primary admin (owner)
  can_manage_admins BOOLEAN DEFAULT false,
  can_manage_branches BOOLEAN DEFAULT true,
  can_view_financials BOOLEAN DEFAULT false,
  assigned_by UUID REFERENCES profiles(id),
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_service_admin_pair UNIQUE(service_id, admin_id)
);

-- =============================================
-- BRANCHES TABLE
-- =============================================
CREATE TABLE public.branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES public.cleaning_services(id) ON DELETE CASCADE,
  branch_name TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT,
  postal_code TEXT,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  service_radius_km DECIMAL(5, 2) DEFAULT 10.0,
  phone TEXT NOT NULL,
  operating_hours JSONB, -- {"monday": {"open": "09:00", "close": "18:00"}, ...}
  status public.branch_status DEFAULT 'active',
  is_active BOOLEAN DEFAULT true, -- Soft delete flag
  created_by UUID NOT NULL REFERENCES profiles(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================
-- BRANCH ADMINS TABLE (Multiple admins per branch)
-- =============================================
CREATE TABLE public.branch_admins (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_primary BOOLEAN DEFAULT false, -- Primary branch manager
  can_manage_cleaners BOOLEAN DEFAULT true,
  can_manage_bookings BOOLEAN DEFAULT true,
  can_view_reports BOOLEAN DEFAULT false,
  assigned_by UUID REFERENCES profiles(id),
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_branch_admin_pair UNIQUE(branch_id, admin_id)
);

-- =============================================
-- CLEANERS TABLE (Staff)
-- =============================================
CREATE TABLE public.cleaners (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  employee_id TEXT,
  id_number TEXT,
  date_of_birth DATE,
  emergency_contact TEXT,
  emergency_phone TEXT,
  status public.cleaner_status DEFAULT 'active',
  leave_start_date DATE,
  leave_end_date DATE,
  termination_date DATE,
  termination_reason TEXT,
  rating DECIMAL(3, 2) DEFAULT 0.00,
  total_jobs INTEGER DEFAULT 0,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================
-- CLEANER BRANCH ASSIGNMENTS (Cleaners can work in multiple branches)
-- =============================================
CREATE TABLE public.cleaner_branch_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cleaner_id UUID NOT NULL REFERENCES public.cleaners(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  is_primary_branch BOOLEAN DEFAULT false,
  assigned_by UUID REFERENCES public.profiles(id),
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_cleaner_branch_pair UNIQUE(cleaner_id, branch_id)
);

-- =============================================
-- CUSTOMERS TABLE
-- =============================================
CREATE TABLE public.customers (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  preferred_payment_method TEXT,
  total_bookings INTEGER DEFAULT 0,
  loyalty_points INTEGER DEFAULT 0,
  registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================
-- CUSTOMER ADDRESSES
-- =============================================
CREATE TABLE public.customer_addresses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  label TEXT DEFAULT 'Home', -- Home, Office, Other
  address_line TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT,
  postal_code TEXT,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
  
  --CONSTRAINT one_default_per_customer UNIQUE(customer_id, is_default) 
    --WHERE is_default = true
);

--- create this and commented above constraint
CREATE UNIQUE INDEX one_default_per_customer 
  ON public.customer_addresses(customer_id) 
  WHERE is_default = true;

-- =============================================
-- INVITATION TOKENS (for staff onboarding)
-- =============================================
CREATE TABLE public.invitation_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT NOT NULL,
  phone TEXT,
  token TEXT UNIQUE NOT NULL,
  role user_role NOT NULL,
  invited_by UUID NOT NULL REFERENCES public.profiles(id),
  service_id UUID REFERENCES public.cleaning_services(id),
  branch_id UUID REFERENCES public.branches(id),
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);