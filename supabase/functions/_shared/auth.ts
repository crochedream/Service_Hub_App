import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export async function getAuthenticatedUser(req: Request) {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    throw new Error('No authorization header');
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    {
      global: {
        headers: { Authorization: authHeader },
      },
    }
  );

  const { data: { user }, error } = await supabase.auth.getUser();
  
  if (error || !user) {
    throw new Error('Unauthorized');
  }

  return { user, supabase };
}

export function createAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  );
}