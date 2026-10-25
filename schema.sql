-- شغّل الملف كاملاً في Supabase > SQL Editor (آمن لإعادة التشغيل)
create table if not exists amb_ambassadors(id uuid primary key default gen_random_uuid(),name text not null,title text,linkedin text,created_at timestamptz default now());
alter table amb_ambassadors add column if not exists number text, add column if not exists code text, add column if not exists city text, add column if not exists bio text,
 add column if not exists instagram text, add column if not exists photo text, add column if not exists registered boolean default false;
create table if not exists amb_points(id uuid primary key default gen_random_uuid(),ambassador_id uuid not null references amb_ambassadors on delete cascade,
 kind text not null check(kind in('interview','ref','li','dm','wa','ch','bonus')),points int not null check(points>0),judge text,question int check(question between 1 and 5),note text,created_at timestamptz default now());
create table if not exists amb_settings(key text primary key,value text);
create table if not exists amb_submissions(id uuid primary key default gen_random_uuid(),ambassador_id uuid not null references amb_ambassadors on delete cascade,day date not null,url text not null,
 status text not null default 'pending' check(status in('pending','approved','rejected')),created_at timestamptz default now(),unique(ambassador_id,day));
alter table amb_ambassadors enable row level security;alter table amb_points enable row level security;alter table amb_settings enable row level security;alter table amb_submissions enable row level security;
drop policy if exists "read" on amb_ambassadors;drop policy if exists "read" on amb_points;drop policy if exists "read" on amb_settings;drop policy if exists "read" on amb_submissions;
drop policy if exists "admin" on amb_ambassadors;drop policy if exists "admin" on amb_points;drop policy if exists "admin" on amb_settings;drop policy if exists "admin" on amb_submissions;
-- السفراء: لا قراءة عامة (يحتوي الرقم السري). العرض العام عبر amb_public فقط
create policy "admin" on amb_ambassadors for all to authenticated using(true) with check(true);
create policy "read" on amb_points for select using(true);create policy "read" on amb_settings for select using(true);create policy "read" on amb_submissions for select using(status='approved' or auth.role()='authenticated');
create policy "admin" on amb_points for all to authenticated using(true) with check(true);create policy "admin" on amb_settings for all to authenticated using(true) with check(true);create policy "admin" on amb_submissions for all to authenticated using(true) with check(true);
create or replace view amb_public as select id,number,name,title,city,bio,linkedin,instagram,photo,registered,created_at from amb_ambassadors;
grant select on amb_public to anon,authenticated;
-- حماية رصيد المحكّمين
create or replace function amb_check() returns trigger language plpgsql as $$ begin
 if new.kind='interview' then
  if new.points>10 then raise exception 'الحد 10 نقاط للسؤال'; end if;
  if coalesce((select sum(points) from amb_points where kind='interview' and judge=new.judge),0)+new.points>50 then raise exception 'رصيد المحكّم لا يكفي'; end if;
 end if; return new; end $$;
drop trigger if exists amb_check on amb_points;create trigger amb_check before insert on amb_points for each row execute function amb_check();
-- نقاط تلقائية عند اعتماد مشاركة
create or replace function amb_approve() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.status='approved' and old.status is distinct from 'approved' then
  insert into amb_points(ambassador_id,kind,points,note) values(new.ambassador_id,'ch',coalesce((select nullif(value,'')::int from amb_settings where key='sp'),10),'مشاركة '||new.day);
 end if; return new; end $$;
drop trigger if exists amb_approve on amb_submissions;create trigger amb_approve after update on amb_submissions for each row execute function amb_approve();
-- بوابة السفير (بالرقم الخاص)
create or replace function amb_claim(p_code text) returns json language plpgsql security definer set search_path=public as $$
declare a amb_ambassadors; begin
 select * into a from amb_ambassadors where code=upper(trim(p_code)); if not found then return null; end if;
 return json_build_object('id',a.id,'number',a.number,'name',a.name,'title',a.title,'city',a.city,'bio',a.bio,'linkedin',a.linkedin,'instagram',a.instagram,'photo',a.photo,'registered',a.registered,
  'points',(select coalesce(sum(points),0) from amb_points where ambassador_id=a.id),
  'subs',(select coalesce(json_agg(json_build_object('day',day,'url',url,'status',status) order by day),'[]'::json) from amb_submissions where ambassador_id=a.id)); end $$;
create or replace function amb_save(p_code text,p_name text,p_title text,p_city text,p_bio text,p_li text,p_ig text,p_photo text) returns boolean language plpgsql security definer set search_path=public as $$ begin
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'الاسم مطلوب'; end if;
 if coalesce(p_li,'')<>'' and p_li not like 'https://%' then raise exception 'رابط لينكدإن يجب أن يبدأ بـ https://'; end if;
 if coalesce(p_ig,'')<>'' and p_ig not like 'https://%' then raise exception 'رابط إنستغرام يجب أن يبدأ بـ https://'; end if;
 if p_photo is not null and (p_photo not like 'data:image/%' or length(p_photo)>150000) then raise exception 'الصورة غير صالحة'; end if;
 update amb_ambassadors set name=left(trim(p_name),80),title=left(p_title,80),city=left(p_city,60),bio=left(p_bio,240),linkedin=nullif(p_li,''),instagram=nullif(p_ig,''),photo=p_photo,registered=true where code=upper(trim(p_code));
 return found; end $$;
create or replace function amb_submit(p_code text,p_url text) returns text language plpgsql security definer set search_path=public as $$
declare a amb_ambassadors; d date:=(now() at time zone 'Asia/Gaza')::date; s date; n int; begin
 select * into a from amb_ambassadors where code=upper(trim(p_code)); if not found then raise exception 'رقم غير صحيح'; end if;
 if p_url not like 'https://%' or length(p_url)>500 then raise exception 'أدخل رابطاً صحيحاً يبدأ بـ https://'; end if;
 select nullif(value,'')::date into s from amb_settings where key='start'; select coalesce(nullif(value,'')::int,7) into n from amb_settings where key='days'; n:=coalesce(n,7);
 if s is null or d<s then raise exception 'لم يبدأ التحدي بعد'; end if; if d>s+n-1 then raise exception 'انتهى التحدي'; end if;
 insert into amb_submissions(ambassador_id,day,url) values(a.id,d,p_url) on conflict(ambassador_id,day) do update set url=excluded.url where amb_submissions.status<>'approved';
 return 'ok'; end $$;
grant execute on function amb_claim(text),amb_save(text,text,text,text,text,text,text,text),amb_submit(text,text) to anon,authenticated;
do $$ begin alter publication supabase_realtime add table amb_points; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table amb_submissions; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table amb_settings; exception when others then null; end $$;

-- الإعلانات
create table if not exists amb_news(id uuid primary key default gen_random_uuid(),text text not null,created_at timestamptz default now());
alter table amb_news enable row level security;drop policy if exists "read" on amb_news;drop policy if exists "admin" on amb_news;
create policy "read" on amb_news for select using(true);create policy "admin" on amb_news for all to authenticated using(true) with check(true);
insert into amb_settings(key,value) values('days','7'),('sp','10') on conflict do nothing;
do $$ begin alter publication supabase_realtime add table amb_news; exception when others then null; end $$;

-- ===== الاستقطاب عبر رسالة لينكدإن + المقابلة (50 للسفير) + عدّاد البداية والنهاية =====
create table if not exists amb_referrals(id uuid primary key default gen_random_uuid(),ambassador_id uuid not null references amb_ambassadors on delete cascade,person_name text not null,linkedin text not null,created_at timestamptz default now());
alter table amb_points add column if not exists referral_id uuid references amb_referrals on delete cascade;
alter table amb_referrals enable row level security;drop policy if exists "admin" on amb_referrals;
create policy "admin" on amb_referrals for all to authenticated using(true) with check(true);
create or replace function amb_ref_norm() returns trigger language plpgsql as $$ begin
 new.linkedin:=regexp_replace(split_part(regexp_replace(lower(trim(new.linkedin)),'^https?://(www\.)?',''),'?',1),'/+$',''); return new; end $$;
drop trigger if exists amb_ref_norm on amb_referrals;create trigger amb_ref_norm before insert on amb_referrals for each row execute function amb_ref_norm();
create unique index if not exists amb_ref_uq on amb_referrals(linkedin);
create or replace function amb_ref_pt() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into amb_points(ambassador_id,kind,points,referral_id,note) values(new.ambassador_id,'ref',coalesce((select nullif(value,'')::int from amb_settings where key='rp'),10),new.id,null); return new; end $$;
drop trigger if exists amb_ref_pt on amb_referrals;create trigger amb_ref_pt after insert on amb_referrals for each row execute function amb_ref_pt();
create or replace function amb_check() returns trigger language plpgsql as $$ begin
 if new.kind='interview' then
  if new.points>10 then raise exception 'الحد 10 نقاط للسؤال'; end if;
  if new.question is null then raise exception 'حدّد رقم السؤال'; end if;
  if exists(select 1 from amb_points where kind='interview' and ambassador_id=new.ambassador_id and question=new.question) then raise exception 'سُجّل هذا السؤال لهذا السفير مسبقاً'; end if;
  if coalesce((select sum(points) from amb_points where kind='interview' and ambassador_id=new.ambassador_id),0)+new.points>50 then raise exception 'مجموع المقابلة لا يتجاوز 50'; end if;
 end if; return new; end $$;
create or replace function amb_claim(p_code text) returns json language plpgsql security definer set search_path=public as $$
declare a amb_ambassadors; begin
 select * into a from amb_ambassadors where code=upper(trim(p_code)); if not found then return null; end if;
 return json_build_object('id',a.id,'number',a.number,'name',a.name,'title',a.title,'city',a.city,'bio',a.bio,'linkedin',a.linkedin,'instagram',a.instagram,'photo',a.photo,'registered',a.registered,
  'points',(select coalesce(sum(points),0) from amb_points where ambassador_id=a.id),
  'refs',(select coalesce(json_agg(json_build_object('n',split_part(person_name,' ',1),'d',created_at::date) order by created_at),'[]'::json) from amb_referrals where ambassador_id=a.id),
  'subs','[]'::json); end $$;
insert into amb_settings(key,value) values('rp','10') on conflict do nothing;

-- ===== خصوصية: لا قراءة عامة لجدول النقاط (فيه أسماء المستقطَبين وتفاصيل المقابلة) =====
drop policy if exists "read" on amb_points;drop policy if exists "read" on amb_submissions;
create or replace view amb_points_public as select id,ambassador_id,kind,points,created_at from amb_points;
grant select on amb_points_public to anon,authenticated;

-- ===== الخصوصية والإخفاء (الإصدار النهائي) =====
alter table amb_ambassadors add column if not exists hidden boolean default false;
create or replace view amb_public as select id,number,name,title,city,bio,linkedin,instagram,photo,registered,created_at from amb_ambassadors where not coalesce(hidden,false);
drop policy if exists "read" on amb_points;
create or replace view amb_points_public as select id,ambassador_id,kind,points,created_at from amb_points;
grant select on amb_public,amb_points_public to anon,authenticated;
update amb_points set note=null where kind='ref';
