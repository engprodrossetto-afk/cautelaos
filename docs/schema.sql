-- ══════════════════════════════════════════════════════════
-- CautelaOS — Schema completo do banco de dados (Supabase/Postgres)
-- Construtora Tripoloni
-- ══════════════════════════════════════════════════════════
-- Execute este script inteiro no SQL Editor de um novo projeto
-- Supabase para recriar a estrutura usada pelo CautelaOS.
-- ══════════════════════════════════════════════════════════

-- ──────────────────────────────────────────
-- TABELA: equipamentos
-- ──────────────────────────────────────────
create table public.equipamentos (
  id bigint generated always as identity primary key,
  nome text not null,
  serie text not null,
  tipo text,
  marca text,
  modelo text,
  origem text not null check (origem in ('proprio','terceiro')),
  status text not null default 'almoxarifado' check (status in ('almoxarifado','cautelado','manutencao','inativo')),
  obs text,
  -- campos de equipamento próprio
  patrimonio text,
  ano integer,
  valor_aq numeric(12,2),
  nf_compra text,
  -- campos de equipamento terceiro
  proprietario text,
  vinculo text check (vinculo in ('locacao','comodato','emprestimo')),
  nf text,
  contrato text,
  dt_ini date,
  dt_fim date,
  valor_loc numeric(12,2),
  contato text,
  criado_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.equipamentos is 'Equipamentos e ferramentas cadastrados, próprios ou de terceiros';

-- ──────────────────────────────────────────
-- TABELA: colaboradores
-- ──────────────────────────────────────────
create table public.colaboradores (
  id bigint generated always as identity primary key,
  matricula text not null unique,
  nome text not null,
  setor text not null,
  encarregado text,
  cargo text,
  tel text,
  cpf text,
  ativo text not null default 'ativo' check (ativo in ('ativo','inativo')),
  criado_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.colaboradores is 'Colaboradores da obra que podem receber cautelas de equipamentos';

-- ──────────────────────────────────────────
-- TABELA: cautelas
-- ──────────────────────────────────────────
create table public.cautelas (
  id bigint generated always as identity primary key,
  equipamento_id bigint not null references public.equipamentos(id) on delete restrict,
  colaborador_id bigint not null references public.colaboradores(id) on delete restrict,
  saida date not null,
  prev date,
  cond_saida text check (cond_saida in ('bom','regular','avariado')),
  obs text,
  status text not null default 'ativa' check (status in ('ativa','devolvida')),
  data_dev date,
  cond_dev text check (cond_dev in ('bom','avariado','manut')),
  obs_dev text,
  registrado_por uuid,
  devolvido_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.cautelas is 'Registros de saída e devolução de equipamentos cautelados a colaboradores';
comment on column public.cautelas.registrado_por is 'Usuário que registrou a saída do equipamento';
comment on column public.cautelas.devolvido_por is 'Usuário que confirmou a devolução';

-- ──────────────────────────────────────────
-- TABELA: manutencao
-- ──────────────────────────────────────────
create table public.manutencao (
  id bigint generated always as identity primary key,
  equipamento_id bigint not null references public.equipamentos(id) on delete restrict,
  defeito text not null,
  prestador text,
  tel_prest text,
  os text,
  entrada date not null,
  prev date,
  tipo text not null default 'corretiva' check (tipo in ('corretiva','preventiva')),
  valor numeric(12,2) default 0,
  valor_final numeric(12,2) default 0,
  obs text,
  status text not null default 'em_andamento' check (status in ('em_andamento','concluida')),
  dt_conclusao date,
  registrado_por uuid,
  concluido_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.manutencao is 'Ordens de serviço de manutenção corretiva ou preventiva';
comment on column public.manutencao.registrado_por is 'Usuário que abriu a OS de manutenção';
comment on column public.manutencao.concluido_por is 'Usuário que marcou a OS como concluída';

-- ──────────────────────────────────────────
-- TABELA: perfis (vinculada ao Supabase Auth)
-- ──────────────────────────────────────────
create table public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  cargo text default 'Almoxarife',
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.perfis is 'Perfil de cada usuário autenticado que opera o CautelaOS';

-- Vincula as foreign keys de auditoria à tabela de perfis
alter table public.cautelas add constraint cautelas_registrado_por_fkey foreign key (registrado_por) references public.perfis(id);
alter table public.cautelas add constraint cautelas_devolvido_por_fkey foreign key (devolvido_por) references public.perfis(id);
alter table public.manutencao add constraint manutencao_registrado_por_fkey foreign key (registrado_por) references public.perfis(id);
alter table public.manutencao add constraint manutencao_concluido_por_fkey foreign key (concluido_por) references public.perfis(id);
alter table public.equipamentos add constraint equipamentos_criado_por_fkey foreign key (criado_por) references public.perfis(id);
alter table public.colaboradores add constraint colaboradores_criado_por_fkey foreign key (criado_por) references public.perfis(id);

-- ──────────────────────────────────────────
-- TRIGGER: cria perfil automaticamente no cadastro
-- ──────────────────────────────────────────
-- perfis ganha coluna de login (nome de usuário, sem domínio de e-mail técnico)
alter table public.perfis add column login text;
comment on column public.perfis.login is 'Nome de usuário usado para login (sem domínio de e-mail técnico)';

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.perfis (id, nome, login)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'login', split_part(new.email,'@',1))
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ──────────────────────────────────────────
-- TRIGGER: atualiza updated_at automaticamente
-- ──────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_equipamentos_updated_at before update on public.equipamentos
  for each row execute function public.set_updated_at();
create trigger trg_colaboradores_updated_at before update on public.colaboradores
  for each row execute function public.set_updated_at();
create trigger trg_cautelas_updated_at before update on public.cautelas
  for each row execute function public.set_updated_at();
create trigger trg_manutencao_updated_at before update on public.manutencao
  for each row execute function public.set_updated_at();

-- ──────────────────────────────────────────
-- ÍNDICES
-- ──────────────────────────────────────────
create index idx_equipamentos_status on public.equipamentos(status);
create index idx_equipamentos_origem on public.equipamentos(origem);
create index idx_cautelas_equipamento on public.cautelas(equipamento_id);
create index idx_cautelas_colaborador on public.cautelas(colaborador_id);
create index idx_cautelas_status on public.cautelas(status);
create index idx_manutencao_equipamento on public.manutencao(equipamento_id);
create index idx_manutencao_status on public.manutencao(status);
create index idx_colaboradores_setor on public.colaboradores(setor);

-- ──────────────────────────────────────────
-- ROW LEVEL SECURITY
-- Acesso restrito por filial: admin vê tudo, almoxarife
-- só vê/edita registros da própria filial.
-- ──────────────────────────────────────────
alter table public.equipamentos enable row level security;
alter table public.colaboradores enable row level security;
alter table public.cautelas enable row level security;
alter table public.manutencao enable row level security;
alter table public.perfis enable row level security;

-- ──────────────────────────────────────────
-- TABELA: filiais (obras)
-- ──────────────────────────────────────────
create table public.filiais (
  id bigint generated always as identity primary key,
  nome text not null unique,
  cidade text,
  uf text,
  ativa boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.filiais is 'Obras/filiais da Tripoloni — cada equipamento e colaborador pertence a uma';

-- perfis ganha papel (role) e filial
alter table public.perfis add column role text not null default 'almoxarife' check (role in ('admin','almoxarife'));
alter table public.perfis add column filial_id bigint references public.filiais(id);

comment on column public.perfis.role is 'admin = vê e edita todas as filiais; almoxarife = restrito à própria filial';
comment on column public.perfis.filial_id is 'Filial à qual o almoxarife pertence (nulo para admin)';

-- equipamentos e colaboradores ganham filial
alter table public.equipamentos add column filial_id bigint references public.filiais(id);
alter table public.colaboradores add column filial_id bigint references public.filiais(id);

create index idx_equipamentos_filial on public.equipamentos(filial_id);
create index idx_colaboradores_filial on public.colaboradores(filial_id);
create index idx_perfis_filial on public.perfis(filial_id);

-- ──────────────────────────────────────────
-- Funções auxiliares para as políticas de RLS
-- security definer + search_path fixo: evita recursão de RLS
-- ao consultar a própria tabela perfis dentro de uma policy.
-- ──────────────────────────────────────────
create or replace function public.is_admin()
returns boolean as $$
  select exists(
    select 1 from public.perfis where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer stable set search_path = public;

create or replace function public.minha_filial()
returns bigint as $$
  select filial_id from public.perfis where id = auth.uid();
$$ language sql security definer stable set search_path = public;

-- ──────────────────────────────────────────
-- EQUIPAMENTOS: admin vê tudo; almoxarife só a própria filial
-- ──────────────────────────────────────────
create policy "Ver equipamentos da filial ou admin ve tudo" on public.equipamentos
  for select to authenticated
  using (public.is_admin() or filial_id = public.minha_filial());

create policy "Criar equipamento na propria filial ou admin" on public.equipamentos
  for insert to authenticated
  with check (public.is_admin() or filial_id = public.minha_filial());

create policy "Editar equipamento da filial ou admin" on public.equipamentos
  for update to authenticated
  using (public.is_admin() or filial_id = public.minha_filial())
  with check (public.is_admin() or filial_id = public.minha_filial());

create policy "Excluir equipamento da filial ou admin" on public.equipamentos
  for delete to authenticated
  using (public.is_admin() or filial_id = public.minha_filial());

-- ──────────────────────────────────────────
-- COLABORADORES: mesma regra
-- ──────────────────────────────────────────
create policy "Ver colaboradores da filial ou admin ve tudo" on public.colaboradores
  for select to authenticated
  using (public.is_admin() or filial_id = public.minha_filial());

create policy "Criar colaborador na propria filial ou admin" on public.colaboradores
  for insert to authenticated
  with check (public.is_admin() or filial_id = public.minha_filial());

create policy "Editar colaborador da filial ou admin" on public.colaboradores
  for update to authenticated
  using (public.is_admin() or filial_id = public.minha_filial())
  with check (public.is_admin() or filial_id = public.minha_filial());

create policy "Excluir colaborador da filial ou admin" on public.colaboradores
  for delete to authenticated
  using (public.is_admin() or filial_id = public.minha_filial());

-- ──────────────────────────────────────────
-- CAUTELAS: filial é herdada do equipamento vinculado
-- ──────────────────────────────────────────
create policy "Ver cautelas da filial do equipamento ou admin" on public.cautelas
  for select to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = cautelas.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Criar cautela se equipamento for da filial ou admin" on public.cautelas
  for insert to authenticated
  with check (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = cautelas.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Editar cautela da filial ou admin" on public.cautelas
  for update to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = cautelas.equipamento_id and e.filial_id = public.minha_filial())
  )
  with check (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = cautelas.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Excluir cautela da filial ou admin" on public.cautelas
  for delete to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = cautelas.equipamento_id and e.filial_id = public.minha_filial())
  );

-- ──────────────────────────────────────────
-- MANUTENÇÃO: mesma lógica de herança via equipamento
-- ──────────────────────────────────────────
create policy "Ver manutencao da filial ou admin" on public.manutencao
  for select to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = manutencao.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Criar manutencao se equipamento for da filial ou admin" on public.manutencao
  for insert to authenticated
  with check (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = manutencao.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Editar manutencao da filial ou admin" on public.manutencao
  for update to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = manutencao.equipamento_id and e.filial_id = public.minha_filial())
  )
  with check (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = manutencao.equipamento_id and e.filial_id = public.minha_filial())
  );

create policy "Excluir manutencao da filial ou admin" on public.manutencao
  for delete to authenticated
  using (
    public.is_admin() or
    exists(select 1 from public.equipamentos e where e.id = manutencao.equipamento_id and e.filial_id = public.minha_filial())
  );

-- ──────────────────────────────────────────
-- FILIAIS: todo autenticado pode ler (para preencher selects),
-- só admin pode criar/editar/excluir filiais
-- ──────────────────────────────────────────
alter table public.filiais enable row level security;

create policy "Qualquer autenticado ve filiais" on public.filiais
  for select to authenticated using (true);

create policy "Somente admin gerencia filiais" on public.filiais
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Usuários autenticados podem ver todos os perfis" on public.perfis
  for select to authenticated using (true);
create policy "Usuário só edita o próprio perfil" on public.perfis
  for update to authenticated using (auth.uid() = id);

-- ──────────────────────────────────────────
-- Função utilitária: promove um usuário a admin pelo e-mail.
-- Use no SQL Editor do Supabase (não é exposta no app):
-- select public.promover_admin('seuemail@tripoloni.com.br');
-- ──────────────────────────────────────────
create or replace function public.promover_admin(p_email text)
returns text as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where email = p_email;
  if v_id is null then
    return 'Usuário não encontrado. Crie a conta primeiro pelo app, depois rode esta função.';
  end if;
  update public.perfis set role = 'admin' where id = v_id;
  return 'Usuário ' || p_email || ' promovido a admin.';
end;
$$ language plpgsql security definer set search_path = public;
