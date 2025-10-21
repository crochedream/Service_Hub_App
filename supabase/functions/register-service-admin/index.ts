import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ServiceAdminRequest {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  phone: string;
  dateOfBirth?: string;
  gender?: string;
  addressLine?: string;
  city?: string;
  state?: string;
  postalCode?: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const dbSchema = Deno.env.get('DB_SCHEMA') || 'public';
    console.log('📂 Schema:', dbSchema);
    
    const body: ServiceAdminRequest = await req.json();
    console.log('📥 Registration request for:', body.email);

    // Validate
    if (!body.email || !body.password || !body.firstName || !body.lastName || !body.phone) {
      return new Response(
        JSON.stringify({ 
          error: 'Missing required fields',
          required: ['email', 'password', 'firstName', 'lastName', 'phone']
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Check existing user
    const { data: existingUser } = await supabaseAdmin
      .schema(dbSchema)
      .from('profiles')
      .select('id')
      .eq('email', body.email)
      .maybeSingle();

    if (existingUser) {
      return new Response(
        JSON.stringify({ error: 'Email already registered' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('👤 Creating auth user...');

    // Create auth user
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: {
        role: 'service_admin',
        first_name: body.firstName,
        last_name: body.lastName,
        phone: body.phone,
        date_of_birth: body.dateOfBirth,
        gender: body.gender,
      },
    });

    if (authError) {
      console.error('❌ Auth error:', authError);
      return new Response(
        JSON.stringify({ error: authError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ Auth user created:', authData.user.id);
    console.log('📝 Creating profile directly (bypassing trigger)...');

    // Create profile directly - don't wait for trigger
    const { error: profileError } = await supabaseAdmin
      .schema(dbSchema)
      .from('profiles')
      .insert({
        id: authData.user.id,
        email: body.email,
        first_name: body.firstName,
        last_name: body.lastName,
        phone: body.phone,
        role: 'service_admin',
        date_of_birth: body.dateOfBirth,
        gender: body.gender,
        address_line: body.addressLine,
        city: body.city,
        state: body.state,
        postal_code: body.postalCode,
      });

    if (profileError) {
      console.error('❌ Profile creation failed:', profileError);
      
      // Rollback auth user
      await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
      
      return new Response(
        JSON.stringify({ 
          error: 'Failed to create profile',
          details: profileError.message
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ Profile created successfully');
    console.log('🎉 Registration complete!');

    return new Response(
      JSON.stringify({
        success: true,
        userId: authData.user.id,
        email: body.email,
        message: 'Account created successfully!',
      }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('💥 Server error:', error);
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});