-- Rode este arquivo no SQL Editor do seu projeto Supabase (uma vez).
-- Depois crie um usuário em Authentication > Users e use o e-mail e a senha dele
-- em CONFIG no Notia. Use apenas a chave "anon" no tablet, nunca a service_role.

create table if not exists notia_snapshots (
  owner uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tabela text not null,
  dados jsonb not null,
  atualizado_em timestamptz not null default now(),
  primary key (owner, tabela)
);

alter table notia_snapshots enable row level security;

create policy "dono le snapshots" on notia_snapshots
  for select using (owner = auth.uid());
create policy "dono grava snapshots" on notia_snapshots
  for insert with check (owner = auth.uid());
create policy "dono atualiza snapshots" on notia_snapshots
  for update using (owner = auth.uid()) with check (owner = auth.uid());

-- Notificações em tempo real (leads, pagamentos...). Quem insere é o seu backend ou
-- webhook, com a service_role guardada no servidor, preenchendo owner com o id do usuário.
create table if not exists notificacoes (
  id bigserial primary key,
  owner uuid not null references auth.users(id) on delete cascade,
  mensagem text not null,
  criado_em timestamptz not null default now()
);

alter table notificacoes enable row level security;

create policy "dono le notificacoes" on notificacoes
  for select using (owner = auth.uid());

alter publication supabase_realtime add table notificacoes;
