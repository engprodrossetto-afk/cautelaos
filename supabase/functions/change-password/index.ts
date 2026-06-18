// supabase/functions/change-password/index.ts
// Permite que o próprio usuário logado troque sua senha.
// Diferente do fluxo padrão do Supabase (que pede e-mail de confirmação),
// este endpoint funciona com login fake (@cautelaos.local) sem e-mail real,
// então exige apenas confirmar a senha atual antes de trocar.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(origin) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Não autenticado." }), {
        status: 401,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerData, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerData?.user) {
      return new Response(JSON.stringify({ error: "Sessão inválida." }), {
        status: 401,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const senhaAtual = String(body.senhaAtual || "");
    const novaSenha = String(body.novaSenha || "");

    if (!novaSenha || novaSenha.length < 4) {
      return new Response(JSON.stringify({ error: "A nova senha deve ter ao menos 4 caracteres." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    // Confirma a senha atual tentando logar com ela (sem isso, qualquer sessão
    // ativa poderia trocar a senha sem saber a atual — risco se o dispositivo for compartilhado)
    const checkClient = createClient(SUPABASE_URL, ANON_KEY);
    const { error: checkErr } = await checkClient.auth.signInWithPassword({
      email: callerData.user.email!,
      password: senhaAtual,
    });
    if (checkErr) {
      return new Response(JSON.stringify({ error: "Senha atual incorreta." }), {
        status: 401,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { error: updateErr } = await adminClient.auth.admin.updateUserById(callerData.user.id, {
      password: novaSenha,
    });

    if (updateErr) {
      return new Response(JSON.stringify({ error: updateErr.message }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err?.message || err) }), {
      status: 500,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  }
});
