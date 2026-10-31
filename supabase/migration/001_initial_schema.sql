-- =========================================================
-- ENERKOS CLOUD
-- Base de datos inicial
-- Version: 001
-- =========================================================

create extension if not exists pgcrypto;

-- =========================================================
-- 1. DISTRIBUIDORAS
-- =========================================================

create table public.distributors (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    name text not null,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    constraint distributors_code_format
        check (code = upper(code) and code ~ '^[A-Z0-9_]+$'),
    constraint distributors_name_not_empty
        check (length(trim(name)) > 0)
);

insert into public.distributors (code, name)
values
    ('CGE', 'CGE'),
    ('ENEL', 'ENEL'),
    ('CHILQUINTA', 'Chilquinta')
on conflict (code) do nothing;

create table public.admin_users (
    user_id uuid primary key references auth.users(id) on delete cascade,
    role text not null
        check (role in ('admin', 'editor', 'approver', 'viewer')),
    active boolean not null default true,
    created_at timestamptz not null default now()
);

-- =========================================================
-- 2. DISPOSITIVOS ENERKOS
-- =========================================================

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    device_code text not null unique,
    device_name text,
    device_token_hash text not null unique,
    active_distributor_id uuid references public.distributors(id),
    region text,
    comuna text,
    sector text,
    network text,
    installation_id uuid not null default gen_random_uuid(),
    status text not null default 'registered'
        check (status in ('registered', 'pilot', 'active', 'disabled')),
    firmware_version text,
    installed_tariff_version_id uuid,
    configuration_completed boolean not null default false,
    initial_report_received_at timestamptz,
    config_updated_at timestamptz,
    last_seen timestamptz,
    config_revision bigint not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint devices_code_not_empty
        check (length(trim(device_code)) > 0),
    constraint devices_token_hash_format
        check (device_token_hash ~ '^[0-9a-f]{64}$'),
    constraint devices_config_revision_nonnegative
        check (config_revision >= 0),
    constraint devices_configuration_reported
        check (
            not configuration_completed
            or (
                active_distributor_id is not null
                and initial_report_received_at is not null
            )
        )
);

-- =========================================================
-- 3. VERSIONES TARIFARIAS
-- payload queda flexible hasta cerrar el formato del motor.
-- =========================================================

create table public.tariff_versions (
    id uuid primary key default gen_random_uuid(),
    distributor_id uuid not null references public.distributors(id),
    version text not null,
    tariff_variant text not null default 'standard',
    schema_version smallint not null default 1,
    effective_from date not null,
    effective_to date,
    status text not null default 'draft'
        check (status in ('draft', 'validated', 'approved', 'published', 'archived')),
    payload jsonb not null,
    sha256 text,
    signature text,
    created_by uuid references auth.users(id) on delete set null,
    validated_by uuid references auth.users(id) on delete restrict,
    validated_at timestamptz,
    approved_by uuid references auth.users(id) on delete restrict,
    approved_at timestamptz,
    published_by uuid references auth.users(id) on delete restrict,
    published_at timestamptz,
    archived_by uuid references auth.users(id) on delete restrict,
    archived_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint tariff_versions_version_not_empty
        check (length(trim(version)) > 0),
    constraint tariff_versions_variant_not_empty
        check (length(trim(tariff_variant)) > 0),
    constraint tariff_versions_schema_version_positive
        check (schema_version > 0),
    constraint tariff_versions_payload_object
        check (jsonb_typeof(payload) = 'object'),
    constraint tariff_versions_payload_size
        check (octet_length(payload::text) <= 262144),
    constraint tariff_versions_sha256_format
        check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
    constraint tariff_versions_signature_not_empty
        check (signature is null or length(trim(signature)) > 0),
    constraint tariff_versions_effective_range
        check (effective_to is null or effective_to >= effective_from),
    constraint tariff_versions_state_metadata
        check (
            (
                status = 'draft'
                and sha256 is null
                and validated_by is null and validated_at is null
                and approved_by is null and approved_at is null
                and published_by is null and published_at is null
                and archived_by is null and archived_at is null
            )
            or (
                status = 'validated'
                and sha256 is not null
                and validated_by is not null and validated_at is not null
                and approved_by is null and approved_at is null
                and published_by is null and published_at is null
                and archived_by is null and archived_at is null
            )
            or (
                status = 'approved'
                and sha256 is not null
                and validated_by is not null and validated_at is not null
                and approved_by is not null and approved_at is not null
                and published_by is null and published_at is null
                and archived_by is null and archived_at is null
            )
            or (
                status = 'published'
                and sha256 is not null
                and validated_by is not null and validated_at is not null
                and approved_by is not null and approved_at is not null
                and published_by is not null and published_at is not null
                and archived_by is null and archived_at is null
            )
            or (
                status = 'archived'
                and sha256 is not null
                and validated_by is not null and validated_at is not null
                and approved_by is not null and approved_at is not null
                and published_by is not null and published_at is not null
                and archived_by is not null and archived_at is not null
            )
        ),
    constraint tariff_versions_distributor_version_unique
        unique (distributor_id, version),
    constraint tariff_versions_id_distributor_unique
        unique (id, distributor_id)
);

alter table public.devices
    add constraint devices_installed_tariff_company_fk
    foreign key (installed_tariff_version_id, active_distributor_id)
    references public.tariff_versions(id, distributor_id)
    on delete restrict;

create index idx_tariff_versions_distributor_status
    on public.tariff_versions(distributor_id, status, effective_from desc);

create index idx_tariff_versions_published
    on public.tariff_versions(distributor_id, effective_from desc, published_at desc)
    where status = 'published';

-- =========================================================
-- 4. HISTORIAL DE CAMBIOS DE DISTRIBUIDORA
-- =========================================================

create table public.distributor_changes (
    id uuid primary key default gen_random_uuid(),
    device_id uuid not null
        references public.devices(id) on delete restrict,
    previous_distributor_id uuid references public.distributors(id),
    new_distributor_id uuid not null references public.distributors(id),
    reported_at timestamptz not null default now(),
    source text not null default 'device'
        check (source in ('device', 'admin')),
    report_id uuid,
    created_at timestamptz not null default now(),
    constraint distributor_changes_report_unique unique (report_id)
);

create index idx_distributor_changes_device
    on public.distributor_changes(device_id, reported_at desc);

-- =========================================================
-- 5. DESPLIEGUES DE ACTUALIZACIONES
-- =========================================================

create table public.deployments (
    id uuid primary key default gen_random_uuid(),
    tariff_version_id uuid not null
        references public.tariff_versions(id) on delete restrict,
    target_type text not null
        check (target_type in ('pilot', 'all', 'selected')),
    status text not null default 'scheduled'
        check (status in ('scheduled', 'published', 'cancelled', 'failed')),
    scheduled_at timestamptz,
    published_at timestamptz,
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint deployments_publish_state check (
        (status = 'published' and published_at is not null)
        or (status <> 'published' and published_at is null)
    )
);

create index idx_deployments_status
    on public.deployments(status, scheduled_at);

create index idx_deployments_tariff_status
    on public.deployments(tariff_version_id, status);

-- =========================================================
-- 6. DISPOSITIVOS ESPECIFICOS SELECCIONADOS
-- =========================================================

create table public.deployment_devices (
    deployment_id uuid not null
        references public.deployments(id) on delete cascade,
    device_id uuid not null
        references public.devices(id) on delete restrict,
    status text not null default 'pending'
        check (status in ('pending', 'sent', 'installed', 'failed', 'rejected')),
    updated_at timestamptz not null default now(),
    primary key (deployment_id, device_id)
);

create index idx_deployment_devices_device
    on public.deployment_devices(device_id, status);

create index idx_deployment_devices_status
    on public.deployment_devices(status);

-- =========================================================
-- 7. REPORTES DE LOS DISPOSITIVOS
-- =========================================================

create table public.device_reports (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null,
    device_id uuid not null
        references public.devices(id) on delete restrict,
    event_type text not null
        check (event_type in (
            'initial_registration',
            'initial_configuration',
            'distributor_changed',
            'tariff_update',
            'heartbeat',
            'firmware_update',
            'error'
        )),
    firmware_version text,
    reported_distributor_id uuid references public.distributors(id),
    reported_tariff_version_id uuid references public.tariff_versions(id),
    result text
        check (result in ('success', 'failed', 'rejected', 'pending')),
    details jsonb not null default '{}'::jsonb,
    reported_at timestamptz not null default now(),
    received_at timestamptz not null default now(),
    constraint device_reports_details_object
        check (jsonb_typeof(details) = 'object'),
    constraint device_reports_event_unique
        unique (device_id, event_id),
    constraint device_reports_device_id_unique
        unique (device_id, id)
);

alter table public.distributor_changes
    add constraint distributor_changes_report_fk
    foreign key (device_id, report_id)
    references public.device_reports(device_id, id)
    on delete restrict;

create index idx_reports_device
    on public.device_reports(device_id, received_at desc);

create index idx_reports_event
    on public.device_reports(event_type, received_at desc);

-- =========================================================
-- 8. HISTORIAL DE AUDITORIA
-- =========================================================

create table public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    actor_user_id uuid references auth.users(id) on delete set null,
    action text not null,
    entity_type text not null,
    entity_id uuid,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint audit_logs_action_not_empty
        check (length(trim(action)) > 0),
    constraint audit_logs_entity_type_not_empty
        check (length(trim(entity_type)) > 0),
    constraint audit_logs_metadata_object
        check (jsonb_typeof(metadata) = 'object')
);

create index idx_audit_created
    on public.audit_logs(created_at desc);

-- =========================================================
-- 9. VALIDACIONES Y CICLO DE VIDA
-- =========================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger devices_set_updated_at
before update on public.devices
for each row execute function public.set_updated_at();

create trigger tariff_versions_set_updated_at
before update on public.tariff_versions
for each row execute function public.set_updated_at();

create trigger deployments_set_updated_at
before update on public.deployments
for each row execute function public.set_updated_at();

create trigger deployment_devices_set_updated_at
before update on public.deployment_devices
for each row execute function public.set_updated_at();

create or replace function public.guard_tariff_version_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        if new.status <> 'draft' then
            raise exception 'Tariff versions must be created as drafts';
        end if;
        return new;
    end if;

    if tg_op = 'DELETE' then
        if old.status <> 'draft' then
            raise exception 'Only draft tariff versions can be deleted';
        end if;
        return old;
    end if;

    if old.status <> 'draft' then
        if old.status = 'validated' then
            if new.status <> 'approved' then
                raise exception 'Validated versions can only be approved';
            end if;
            if new.approved_by is null or new.approved_at is null then
                raise exception 'Approval requires an approver and timestamp';
            end if;
            if new.approved_by = old.validated_by
               or (old.created_by is not null and new.approved_by = old.created_by) then
                raise exception 'The creator and validator cannot approve the same version';
            end if;
        elsif old.status = 'approved' then
            if new.status <> 'published' then
                raise exception 'Approved versions can only be published';
            end if;
            if new.approved_by is distinct from old.approved_by
               or new.approved_at is distinct from old.approved_at
               or new.published_by is null or new.published_at is null then
                raise exception 'Publishing requires the original approval and a publisher';
            end if;
        elsif old.status = 'published' then
            if new.status <> 'archived' then
                raise exception 'Published versions can only be archived';
            end if;
            if new.published_by is distinct from old.published_by
               or new.published_at is distinct from old.published_at
               or new.archived_by is null or new.archived_at is null then
                raise exception 'Archiving requires the original publication and an archiver';
            end if;
        else
            raise exception 'Archived tariff versions are immutable';
        end if;

        if new.id is distinct from old.id
           or new.distributor_id is distinct from old.distributor_id
           or new.version is distinct from old.version
           or new.tariff_variant is distinct from old.tariff_variant
           or new.schema_version is distinct from old.schema_version
           or new.effective_from is distinct from old.effective_from
           or new.effective_to is distinct from old.effective_to
           or new.payload is distinct from old.payload
           or new.sha256 is distinct from old.sha256
           or new.signature is distinct from old.signature
           or new.created_by is distinct from old.created_by
           or new.validated_by is distinct from old.validated_by
           or new.validated_at is distinct from old.validated_at
           or new.created_at is distinct from old.created_at then
            raise exception 'Validated tariff content is immutable; create a new version';
        end if;
    elsif new.status = 'draft' then
        if new.sha256 is not null
           or new.validated_by is not null or new.validated_at is not null
           or new.approved_by is not null or new.approved_at is not null
           or new.published_by is not null or new.published_at is not null
           or new.archived_by is not null or new.archived_at is not null then
            raise exception 'Draft versions cannot contain lifecycle metadata';
        end if;
    elsif new.status = 'validated' then
        if new.sha256 is null
           or new.validated_by is null or new.validated_at is null
           or new.approved_by is not null or new.approved_at is not null
           or new.published_by is not null or new.published_at is not null
           or new.archived_by is not null or new.archived_at is not null then
            raise exception 'Validation requires a checksum and validator';
        end if;
        if new.created_by is not null and new.validated_by = new.created_by then
            raise exception 'The version creator cannot validate the same version';
        end if;
        if not exists (
            select 1
            from public.distributors
            where id = new.distributor_id
              and enabled
        ) then
            raise exception 'Only enabled distributors can publish tariff versions';
        end if;
    else
        raise exception 'Draft versions can only be validated';
    end if;

    return new;
end;
$$;

create trigger tariff_versions_guard_lifecycle
before insert or update or delete on public.tariff_versions
for each row execute function public.guard_tariff_version_lifecycle();

create or replace function public.validate_device_tariff_and_config()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'UPDATE'
       and new.active_distributor_id is distinct from old.active_distributor_id then
        new.installed_tariff_version_id = null;
    end if;

    if new.configuration_completed
       and (
           new.active_distributor_id is null
           or new.initial_report_received_at is null
       ) then
        raise exception 'A configured device must report its distributor';
    end if;

    if new.configuration_completed and not exists (
        select 1
        from public.distributors
        where id = new.active_distributor_id
          and enabled
    ) then
        raise exception 'A configured device must use an enabled distributor';
    end if;

    if new.installed_tariff_version_id is not null and not exists (
        select 1
        from public.tariff_versions
        where id = new.installed_tariff_version_id
          and distributor_id = new.active_distributor_id
          and status = 'published'
    ) then
        raise exception 'Installed tariff must be published for the active distributor';
    end if;

    return new;
end;
$$;

create trigger devices_validate_tariff_and_config
before insert or update of active_distributor_id, installed_tariff_version_id,
    configuration_completed, initial_report_received_at
on public.devices
for each row execute function public.validate_device_tariff_and_config();

create or replace function public.validate_tariff_deployment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        if new.status <> 'scheduled' then
            raise exception 'Deployments must be created as scheduled';
        end if;
    end if;

    if tg_op = 'DELETE' then
        raise exception 'Deployments are retained for audit; cancel scheduled deployments instead';
    end if;

    if new.status = 'published' and not exists (
        select 1
        from public.tariff_versions tv
        join public.distributors d on d.id = tv.distributor_id
        where tv.id = new.tariff_version_id
          and tv.status = 'published'
          and d.enabled
    ) then
        raise exception 'A deployment requires a published tariff version';
    end if;

    if tg_op = 'UPDATE' and old.status <> 'scheduled' then
        raise exception 'Only scheduled deployments can be changed';
    end if;

    if tg_op = 'UPDATE'
       and exists (
           select 1
           from public.deployment_devices
           where deployment_id = old.id
       )
       and (
           new.tariff_version_id is distinct from old.tariff_version_id
           or new.target_type is distinct from old.target_type
       ) then
        raise exception 'A deployment with assigned devices cannot change its tariff or target';
    end if;

    return new;
end;
$$;

create trigger deployments_validate
before insert or update or delete on public.deployments
for each row execute function public.validate_tariff_deployment();

create or replace function public.validate_deployment_device()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    deployment_target text;
    deployment_status text;
    version_distributor uuid;
    device_distributor uuid;
    device_status text;
    device_configured boolean;
begin
    select d.target_type, d.status, tv.distributor_id, dv.active_distributor_id,
           dv.status, dv.configuration_completed
      into deployment_target, deployment_status, version_distributor, device_distributor,
           device_status, device_configured
    from public.deployments d
    join public.tariff_versions tv on tv.id = d.tariff_version_id
    join public.devices dv on dv.id = new.device_id
    where d.id = new.deployment_id;

    if not found then
        raise exception 'Deployment or device does not exist';
    end if;

    if deployment_target <> 'selected' then
        raise exception 'Only selected deployments accept explicit device assignments';
    end if;

    if version_distributor is distinct from device_distributor then
        raise exception 'Deployment tariff distributor must match the device configuration';
    end if;

    if device_status not in ('active', 'pilot') or not device_configured then
        raise exception 'Only active or pilot configured devices can be assigned';
    end if;

    if new.status <> 'pending' then
        raise exception 'Device assignments must start as pending';
    end if;

    if deployment_status <> 'scheduled' then
        raise exception 'Devices can only be assigned to scheduled deployments';
    end if;

    return new;
end;
$$;

create trigger deployment_devices_validate
before insert on public.deployment_devices
for each row execute function public.validate_deployment_device();

create or replace function public.validate_deployment_publish()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.status = 'published' then
        if new.target_type = 'selected' and not exists (
            select 1
            from public.deployment_devices
            where deployment_id = new.id
        ) then
            raise exception 'A selected deployment must include at least one device';
        end if;

        if new.target_type = 'selected' and exists (
            select 1
            from public.deployment_devices dd
            join public.devices dv on dv.id = dd.device_id
            join public.tariff_versions tv on tv.id = new.tariff_version_id
            where dd.deployment_id = new.id
              and (
                  dv.active_distributor_id is distinct from tv.distributor_id
                  or dv.status not in ('active', 'pilot')
                  or not dv.configuration_completed
              )
        ) then
            raise exception 'Every selected device must remain configured and match the tariff distributor';
        end if;

        if new.target_type = 'pilot' and not exists (
            select 1
            from public.devices dv
            join public.tariff_versions tv
              on tv.id = new.tariff_version_id
             and tv.distributor_id = dv.active_distributor_id
            where dv.status = 'pilot'
              and dv.configuration_completed
              and exists (
                  select 1 from public.distributors
                  where id = tv.distributor_id and enabled
              )
        ) then
            raise exception 'No configured pilot device matches this tariff distributor';
        end if;
    end if;

    if tg_op = 'UPDATE' and old.status <> 'scheduled' then
        raise exception 'Published or finished deployments are immutable';
    end if;

    return new;
end;
$$;

create trigger deployments_validate_publish
before insert or update on public.deployments
for each row execute function public.validate_deployment_publish();

create or replace function public.validate_deployment_device_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    deployment_status text;
begin
    select status into deployment_status
    from public.deployments
    where id = old.deployment_id;

    if tg_op = 'DELETE' then
        if deployment_status <> 'scheduled' then
            raise exception 'Assignments of published or finished deployments are immutable';
        end if;
        return old;
    end if;

    if new.deployment_id is distinct from old.deployment_id
       or new.device_id is distinct from old.device_id then
        raise exception 'A deployment assignment cannot be moved to another device';
    end if;

    if deployment_status <> 'published' then
        raise exception 'Only published deployments accept device status reports';
    end if;

    if not (
        (old.status = 'pending' and new.status in ('sent', 'failed', 'rejected'))
        or (old.status = 'sent' and new.status in ('installed', 'failed', 'rejected'))
    ) then
        raise exception 'Invalid deployment device status transition';
    end if;

    return new;
end;
$$;

create trigger deployment_devices_guard_update
before update or delete on public.deployment_devices
for each row execute function public.validate_deployment_device_update();

-- =========================================================
-- 10. INDICES ADICIONALES
-- =========================================================

create index idx_devices_distributor
    on public.devices(active_distributor_id);

create index idx_devices_status
    on public.devices(status);

create index idx_devices_last_seen
    on public.devices(last_seen desc);

create index idx_reports_tariff
    on public.device_reports(reported_tariff_version_id, received_at desc);

-- =========================================================
-- 11. SEGURIDAD
-- El acceso de dispositivos y paneles se realiza mediante el Worker.
-- No se permite acceso directo desde clientes publicos.
-- =========================================================

alter table public.admin_users enable row level security;
alter table public.distributors enable row level security;
alter table public.devices enable row level security;
alter table public.tariff_versions enable row level security;
alter table public.distributor_changes enable row level security;
alter table public.deployments enable row level security;
alter table public.deployment_devices enable row level security;
alter table public.device_reports enable row level security;
alter table public.audit_logs enable row level security;

revoke all on public.admin_users from anon, authenticated;
revoke all on public.distributors from anon, authenticated;
revoke all on public.devices from anon, authenticated;
revoke all on public.tariff_versions from anon, authenticated;
revoke all on public.distributor_changes from anon, authenticated;
revoke all on public.deployments from anon, authenticated;
revoke all on public.deployment_devices from anon, authenticated;
revoke all on public.device_reports from anon, authenticated;
revoke all on public.audit_logs from anon, authenticated;

grant all on public.admin_users to service_role;
grant all on public.distributors to service_role;
grant all on public.devices to service_role;
grant all on public.tariff_versions to service_role;
grant all on public.distributor_changes to service_role;
grant all on public.deployments to service_role;
grant all on public.deployment_devices to service_role;
grant all on public.device_reports to service_role;
grant all on public.audit_logs to service_role;
grant usage, select on all sequences in schema public to service_role;

-- =========================================================
-- FIN DE LA MIGRACIÓN INICIAL
-- =========================================================
