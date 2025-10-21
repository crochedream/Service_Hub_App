import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface CleaningServiceRequest {
  businessName: string;
  businessLicense?: string;
  businessAddress: string;
  logoUrl?: string;
  description?: string;
  phone: string;
  email: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body: CleaningServiceRequest = await req.json();
    
    // Get environment configuration
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const dbSchema = Deno.env.get('DB_SCHEMA') || 'public';
    
    console.log('🌍 Environment:', supabaseUrl);
    console.log('📂 Schema:', dbSchema);
    console.log('🏢 Registration request for:', body.businessName);

    // Validate required fields
    if (!body.businessName || !body.businessAddress || !body.phone || !body.email) {
      return new Response(
        JSON.stringify({ 
          error: 'Missing required fields',
          required: ['businessName', 'businessAddress', 'phone', 'email']
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create Supabase client with user's JWT token
    const supabase = createClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    );

    // Get authenticated user
    console.log('🔐 Verifying authentication...');
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      console.error('❌ Authentication failed:', authError);
      return new Response(
        JSON.stringify({ error: 'Unauthorized. Please login first.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ User authenticated:', user.id);

    // Verify user is a service_admin
    console.log('🔍 Checking user role...');
    const { data: profile, error: profileError } = await supabase
      .schema(dbSchema)
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      console.error('❌ Profile not found:', profileError);
      return new Response(
        JSON.stringify({ error: 'User profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (profile.role !== 'service_admin') {
      console.error('❌ Insufficient permissions. User role:', profile.role);
      return new Response(
        JSON.stringify({ 
          error: 'Only service admins can register cleaning services',
          currentRole: profile.role
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ User is authorized as service_admin');

    // Check if user already has a cleaning service
    console.log('🔍 Checking for existing services...');
    const { data: existingService } = await supabase
      .schema(dbSchema)
      .from('cleaning_services')
      .select('id, business_name')
      .eq('created_by', user.id)
      .maybeSingle();

    if (existingService) {
      console.log('⚠️ User already has a service:', existingService.business_name);
      return new Response(
        JSON.stringify({ 
          error: 'You already have a registered cleaning service',
          existingService: {
            id: existingService.id,
            name: existingService.business_name
          }
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if business email already exists
    console.log('🔍 Checking if business email is already registered...');
    const { data: duplicateEmail } = await supabase
      .schema(dbSchema)
      .from('cleaning_services')
      .select('id, business_name')
      .eq('email', body.email)
      .maybeSingle();

    if (duplicateEmail) {
      console.log('⚠️ Business email already in use:', body.email);
      return new Response(
        JSON.stringify({ 
          error: 'Business email is already registered',
          existingService: duplicateEmail.business_name
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('🏢 Creating cleaning service...');

    // Create cleaning service (trigger will automatically add to service_admins)
    const { data: service, error: serviceError } = await supabase
      .schema(dbSchema)
      .from('cleaning_services')
      .insert({
        business_name: body.businessName,
        business_license: body.businessLicense,
        business_address: body.businessAddress,
        logo_url: body.logoUrl,
        description: body.description,
        phone: body.phone,
        email: body.email,
        created_by: user.id,
        status: 'pending_approval',
      })
      .select()
      .single();

    if (serviceError) {
      console.error('❌ Failed to create cleaning service:', serviceError);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to create cleaning service',
          details: serviceError.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ Cleaning service created:', service.id);

    // Wait a moment for trigger to add service_admin record
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Verify service_admin record was created by trigger
    console.log('🔍 Verifying service_admin assignment...');
    const { data: serviceAdmin } = await supabase
      .schema(dbSchema)
      .from('service_admins')
      .select('id, is_primary, can_manage_admins')
      .eq('service_id', service.id)
      .eq('admin_id', user.id)
      .maybeSingle();

    if (!serviceAdmin) {
      console.warn('⚠️ Service admin record not created by trigger, creating manually...');
      
      // Manually create service_admin as fallback
      const { error: manualAdminError } = await supabase
        .schema(dbSchema)
        .from('service_admins')
        .insert({
          service_id: service.id,
          admin_id: user.id,
          is_primary: true,
          can_manage_admins: true,
          can_manage_branches: true,
          can_view_financials: true,
        });

      if (manualAdminError) {
        console.error('❌ Failed to create service_admin record:', manualAdminError);
        // Don't fail the entire operation, just log for manual fix
      } else {
        console.log('✅ Service admin created manually');
      }
    } else {
      console.log('✅ Service admin assigned by trigger');
    }

    console.log('🎉 Cleaning service registration complete!');

    return new Response(
      JSON.stringify({
        success: true,
        service: {
          id: service.id,
          businessName: service.business_name,
          status: service.status,
          email: service.email,
          phone: service.phone,
          businessAddress: service.business_address,
        },
        message: 'Cleaning service registered successfully! Your service is pending approval.',
        nextSteps: [
          'Your service is under review by our admin team',
          'You will receive an email notification once approved',
          'After approval, you can start creating branches and adding staff'
        ]
      }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('💥 Server error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error.message || 'Unknown error occurred'
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});