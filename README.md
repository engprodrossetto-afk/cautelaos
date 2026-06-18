# CautelaOS

Sistema de gestão de cautelas de equipamentos e ferramentas para a **Construtora Tripoloni**.

Controla o ciclo de vida completo de equipamentos próprios e de terceiros: cadastro, cautela a colaboradores, devolução, manutenção corretiva/preventiva e relatórios gerenciais.

## Stack

- **Front-end:** HTML + CSS + JavaScript puro (single-page, sem build step)
- **Backend:** [Supabase](https://supabase.com) (Postgres + Auth + RLS)
- **Hospedagem:** GitHub Pages (estático)

## Funcionalidades

- Cadastro de equipamentos (próprios com plaqueta de patrimônio, ou de terceiros com contrato/locação)
- Cadastro de colaboradores por matrícula, setor e encarregado
- Emissão e devolução de cautelas, com localização sempre rastreada (almoxarifado / colaborador / manutenção)
- Abertura automática de OS de manutenção quando um equipamento é devolvido com defeito
- Relatórios por período, setor, colaborador e manutenções
- Histórico completo por equipamento
- **Controle por filial (obra):** cada equipamento e colaborador pertence a uma filial
- **Dois papéis de usuário:**
  - `admin` — vê e edita dados de todas as filiais, gerencia filiais e usuários
  - `almoxarife` — vê e edita apenas os dados da própria filial (login individual com auditoria de quem fez cada ação)
- Layout responsivo com navegação inferior dedicada para uso em celular

## Login dos usuários

Os almoxarifes **não usam e-mail real** — apenas um nome de usuário (login) e senha definidos pelo administrador. Internamente, o Supabase Auth ainda exige um e-mail, então o sistema gera um endereço técnico no formato `login@cautelaos.local` que nunca aparece na interface.

Não existe autocadastro: contas só são criadas pelo administrador, na tela **Administração → Usuários → Novo usuário**. Isso depende de duas Edge Functions (em `supabase/functions/`) que precisam estar implantadas no projeto Supabase:

- **`admin-create-user`** — cria o login e a senha de um novo usuário (só pode ser chamada por quem já é admin)
- **`change-password`** — permite que o próprio usuário troque a senha depois do primeiro acesso

Para implantar, com a [Supabase CLI](https://supabase.com/docs/guides/cli):
```bash
supabase functions deploy admin-create-user --project-ref SEU_PROJECT_REF
supabase functions deploy change-password --project-ref SEU_PROJECT_REF
```

## Promovendo o primeiro administrador

Como não existe autocadastro, o primeiro usuário precisa ser criado direto no banco:

1. No SQL Editor do Supabase, crie seu próprio usuário admin manualmente (substitua os valores):
   ```sql
   -- Via Supabase Dashboard: Authentication → Users → Add user
   -- Email: seulogin@cautelaos.local | Senha: sua senha inicial | marque "Auto Confirm User"
   ```
2. Depois, promova-o a admin:
   ```sql
   select public.promover_admin('seulogin@cautelaos.local');
   ```
3. Faça login no app digitando apenas `seulogin` (sem o domínio) — agora você verá o menu "Administração"

A partir daí, use **Administração → Filiais** para cadastrar as obras, e **Administração → Usuários → Novo usuário** para criar o login e a senha de cada almoxarife, já vinculado à filial certa.

## Configuração do banco de dados

O schema completo (tabelas, RLS, triggers) está documentado em [`docs/schema.sql`](docs/schema.sql).
Para rodar este projeto com seu próprio Supabase:

1. Crie um projeto em [supabase.com](https://supabase.com)
2. Rode o conteúdo de `docs/schema.sql` no SQL Editor do seu projeto
3. Em `index.html`, substitua `SUPABASE_URL` e `SUPABASE_ANON_KEY` pelas credenciais do seu projeto (Project Settings → API)
4. Em **Authentication → Providers**, confirme que "Email" está habilitado

## Publicação

Este projeto é 100% estático — qualquer hospedagem de arquivos serve. Para GitHub Pages:

1. Settings → Pages → Branch: `main` → pasta `/ (root)`
2. A URL pública aparece em alguns minutos: `https://SEU_USUARIO.github.io/cautelaos/`

## Desenvolvimento local

Não há dependências de build. Basta abrir `index.html` em um navegador, ou servir com qualquer servidor estático:

```bash
python3 -m http.server 8000
# acesse http://localhost:8000
```

## Estrutura

```
.
├── index.html       # aplicação completa (front-end)
├── docs/
│   └── schema.sql    # schema do banco de dados Supabase
└── README.md
```

---

Desenvolvido para uso interno da Construtora Tripoloni.
