// supabase/functions/admin-create-user/index.ts
// Permite que um usuário com role='admin' crie novos almoxarifes
// usando apenas "nome de usuário" + senha (sem exigir e-mail real).
// Internamente, gera um e-mail técnico no domínio @cautelaos.local
// que nunca é exposto na interface — o usuário final só vê o login.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const EMAIL_DOMAIN = "cautelaos.local";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function normalizeLogin(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "") // remove acentos
    .replace(/[^a-z0-9._-]/g, ""); // só caracteres seguros para a parte local de um e-mail
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

    // Cliente "do chamador" — usado só para verificar QUEM está chamando e se é admin
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

    // Cliente admin — única instância com permissão de criar usuários
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerProfile, error: profileErr } = await adminClient
      .from("perfis")
      .select("role")
      .eq("id", callerData.user.id)
      .single();

    if (profileErr || !callerProfile || callerProfile.role !== "admin") {
      return new Response(JSON.stringify({ error: "Apenas administradores podem criar usuários." }), {
        status: 403,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const loginRaw = String(body.login || "");
    const senha = String(body.senha || "");
    const nome = String(body.nome || "").trim();
    const role = body.role === "admin" ? "admin" : "almoxarife";
    const filialId = body.filialId ? Number(body.filialId) : null;

    const login = normalizeLogin(loginRaw);
    if (!login || login.length < 3) {
      return new Response(JSON.stringify({ error: "Login deve ter ao menos 3 caracteres (letras, números, ponto, hífen)." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }
    if (!senha || senha.length < 4) {
      return new Response(JSON.stringify({ error: "Senha deve ter ao menos 4 caracteres." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }
    if (!nome) {
      return new Response(JSON.stringify({ error: "Nome completo é obrigatório." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }
    if (role === "almoxarife" && !filialId) {
      return new Response(JSON.stringify({ error: "Selecione uma filial para o almoxarife." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const fakeEmail = `${login}@${EMAIL_DOMAIN}`;

    // Verifica se o login já existe (e-mail técnico já cadastrado)
    const { data: existingUsers } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const jaExiste = existingUsers?.users?.some((u) => u.email === fakeEmail);
    if (jaExiste) {
      return new Response(JSON.stringify({ error: `O login "${login}" já está em uso.` }), {
        status: 409,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const { data: newUser, error: createErr } = await adminClient.auth.admin.createUser({
      email: fakeEmail,
      password: senha,
      email_confirm: true, // pula a etapa de confirmação por e-mail (não existe e-mail real)
      user_metadata: { nome, login },
    });

    if (createErr || !newUser?.user) {
      return new Response(JSON.stringify({ error: createErr?.message || "Erro ao criar usuário." }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    // O trigger handle_new_user já cria a linha em perfis (role padrão 'almoxarife').
    // Aqui atualizamos com o role e a filial corretos definidos pelo admin.
    const { error: updateErr } = await adminClient
      .from("perfis")
      .update({ role, filial_id: filialId, nome })
      .eq("id", newUser.user.id);

    if (updateErr) {
      return new Response(JSON.stringify({ error: "Usuário criado, mas falha ao definir papel/filial: " + updateErr.message }), {
        status: 207,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, login, id: newUser.user.id }), {
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
