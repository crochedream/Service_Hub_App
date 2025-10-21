-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION speclean_services.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON speclean_services.profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cleaning_services_updated_at BEFORE UPDATE ON speclean_services.cleaning_services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON speclean_services.branches
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to automatically create profile when auth user is created
CREATE OR REPLACE FUNCTION speclean_services.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO speclean_services.profiles (id, role, first_name, last_name, phone, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'customer')::user_role,
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
	COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
    COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
    NEW.email
  );
  
  -- If role is customer, also create customer record
  IF COALESCE(NEW.raw_user_meta_data->>'role', 'customer') = 'customer' THEN
    INSERT INTO speclean_services.customers (id)
    VALUES (NEW.id);
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail auth user creation
    RAISE WARNING 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger to automatically create profile on auth user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION speclean_services.handle_new_user();

-- Function to add service admin after service is created
CREATE OR REPLACE FUNCTION speclean_services.add_service_admin_on_service_creation()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO speclean_services.service_admins (service_id, admin_id, is_primary, can_manage_admins, can_manage_branches, can_view_financials)
  VALUES (NEW.id, NEW.created_by, true, true, true, true);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_service_created_add_admin
  AFTER INSERT ON speclean_services.cleaning_services
  FOR EACH ROW EXECUTE FUNCTION add_service_admin_on_service_creation();

