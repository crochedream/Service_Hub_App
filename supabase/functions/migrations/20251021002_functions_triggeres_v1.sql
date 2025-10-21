-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cleaning_services_updated_at BEFORE UPDATE ON public.cleaning_services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON public.branches
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- Function to add service admin after service is created
CREATE OR REPLACE FUNCTION public.add_service_admin_on_service_creation()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.service_admins (service_id, admin_id, is_primary, can_manage_admins, can_manage_branches, can_view_financials)
  VALUES (NEW.id, NEW.created_by, true, true, true, true);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_service_created_add_admin
  AFTER INSERT ON public.cleaning_services
  FOR EACH ROW EXECUTE FUNCTION add_service_admin_on_service_creation();

