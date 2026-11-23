-- #6998: replace both DesignFlow customer copies with the same ColdLion feed.
-- derived-from: 20260905104825, 20260824011750
begin;

-- Bound lock acquisition when Tracking or the source refresh is busy.
set local lock_timeout = '5s';
set local timezone = 'UTC';

-- The source loader updates rows by (company_code, customer_code) and retains
-- codes absent from subsequent snapshots. Negative IDs cannot collide with
-- archived positive IDs. Read-only views retain the original ID per consumer.
alter table coldlion.customer add column designflow_customer_id integer
  generated always as identity (start with -1 increment by -1);

do $preflight$
begin
  if exists (select 1 from core."externalCustomer" where id <= 0)
     or exists (select 1 from dflow_prod."externalCustomer" where id <= 0) then
    raise exception 'D1: legacy ID collides with the ColdLion ID namespace';
  end if;

  -- Compare order joins, including customers that had no match before. The
  -- Tracking grid and customer filter use codes, labels and IDs, never active.
  if exists (
    with order_codes as (
      select 'core' as reader, "customerCode" as code from plm."ProdOrderHeader"
      union
      select 'production', "customerCode" from dflow_prod."ProdOrderHeader"
    ), previous_customers as (
      select 'core' as reader, "customerCode" as code, "customerDesc" as label
      from core."externalCustomer"
      union all
      select 'production', "customerCode", "customerDesc"
      from dflow_prod."externalCustomer"
    )
    select 1
    from order_codes orders
    left join previous_customers previous
      on previous.reader = orders.reader and previous.code = orders.code
    left join coldlion.customer customer
      on customer.company_code = 'EDGEHOME' and customer.customer_code = orders.code
    where (previous.code is null) <> (customer.customer_code is null)
       or previous.label is distinct from customer.customer_desc
  ) then
    raise exception 'D1: switching sources would change Tracking customer matches or labels';
  end if;
end;
$preflight$;

-- Both legacy tables have identically named indexes and identity sequences.
-- Give each archived object a distinct name before moving it.
alter table core."externalCustomer" rename constraint "externalCustomer_pkey" to external_customer_core_6998_pkey;
alter sequence core."externalCustomer_id_seq" rename to external_customer_core_6998_id_seq;
alter table dflow_prod."externalCustomer" rename constraint "externalCustomer_pkey" to external_customer_prod_6998_pkey;
alter sequence dflow_prod."externalCustomer_id_seq" rename to external_customer_prod_6998_id_seq;

alter table core."externalCustomer" rename to external_customer_core_6998;
alter table core.external_customer_core_6998 set schema archive;
alter table dflow_prod."externalCustomer" rename to external_customer_prod_6998;
alter table dflow_prod.external_customer_prod_6998 set schema archive;

-- Use the current ERP active value for every row. The 767 legacy core flags
-- differ, but activity is not a filter on the Tracking reader.
create view archive.external_customer_feed_6998 with (security_barrier = true) as
select
  customer.designflow_customer_id,
  customer.company_code::varchar as "companyCode",
  customer.customer_code::varchar as "customerCode",
  customer.active::varchar as active,
  customer.address1::varchar as address1,
  customer.address2::varchar as address2,
  customer.ar_customer_code::varchar as "aRCustomerCode",
  customer.city::varchar as city,
  customer.country_code::varchar as "countryCode",
  customer.customer_desc::varchar as "customerDesc",
  customer.customer_type_code::varchar as "customerTypeCode",
  customer.fax_no::varchar as "faxNo",
  customer.phone_no::varchar as "phoneNo",
  customer.state::varchar as state,
  customer.use_consolidated_invoice::varchar as "useConsolidatedInvoice",
  customer.zip_code::varchar as "zipCode",
  customer.parent_customer_code::varchar as "parentCustomerCode",
  customer.customer_dba::varchar as "customerDBA",
  customer.udf01::varchar as udf01,
  customer.udf02::varchar as udf02,
  customer.udf03::varchar as udf03,
  customer.udf04::varchar as udf04,
  customer.udf_date01::varchar as "udfDate01",
  customer.udf_date02::varchar as "udfDate02",
  customer.old_customer_code::varchar as "oldCustomerCode",
  customer.vendor_number::varchar as "vendorNumber",
  customer.address3::varchar as address3,
  customer.region_code::varchar as "regionCode",
  customer.ds_cat::varchar as "dsCat",
  customer.sales_person_code1::varchar as "salesPersonCode1",
  customer.sales_person_code2::varchar as "salesPersonCode2",
  customer.commission_perc1::varchar as "commissionPerc1",
  customer.commission_perc2::varchar as "commissionPerc2",
  customer.factor_code::varchar as "factorCode",
  customer.currency_code::varchar as "currencyCode",
  customer.gl_code::varchar as "glCode",
  customer.created_time::varchar as "createdTime",
  customer.created_user::varchar as "createdUser",
  customer.mod_time::varchar as "modTime",
  customer.mod_user::varchar as "modUser"
from coldlion.customer customer
where customer.company_code = 'EDGEHOME';

create view core."externalCustomer" with (security_barrier = true) as
select
  coalesce(previous.id, feed.designflow_customer_id) as id,
  feed."companyCode",
  feed."customerCode",
  feed.active,
  feed.address1,
  feed.address2,
  feed."aRCustomerCode",
  feed.city,
  feed."countryCode",
  feed."customerDesc",
  feed."customerTypeCode",
  feed."faxNo",
  feed."phoneNo",
  feed.state,
  feed."useConsolidatedInvoice",
  feed."zipCode",
  feed."parentCustomerCode",
  feed."customerDBA",
  feed.udf01,
  feed.udf02,
  feed.udf03,
  feed.udf04,
  feed."udfDate01",
  feed."udfDate02",
  feed."oldCustomerCode",
  feed."vendorNumber",
  feed.address3,
  feed."regionCode",
  feed."dsCat",
  feed."salesPersonCode1",
  feed."salesPersonCode2",
  feed."commissionPerc1",
  feed."commissionPerc2",
  feed."factorCode",
  feed."currencyCode",
  feed."glCode",
  feed."createdTime",
  feed."createdUser",
  feed."modTime",
  feed."modUser"
from archive.external_customer_feed_6998 feed
left join archive.external_customer_core_6998 previous using ("customerCode");

create view dflow_prod."externalCustomer" with (security_barrier = true) as
select
  coalesce(previous.id, feed.designflow_customer_id) as id,
  feed."companyCode",
  feed."customerCode",
  feed.active,
  feed.address1,
  feed.address2,
  feed."aRCustomerCode",
  feed.city,
  feed."countryCode",
  feed."customerDesc",
  feed."customerTypeCode",
  feed."faxNo",
  feed."phoneNo",
  feed.state,
  feed."useConsolidatedInvoice",
  feed."zipCode",
  feed."parentCustomerCode",
  feed."customerDBA",
  feed.udf01,
  feed.udf02,
  feed.udf03,
  feed.udf04,
  feed."udfDate01",
  feed."udfDate02",
  feed."oldCustomerCode",
  feed."vendorNumber",
  feed.address3,
  feed."regionCode",
  feed."dsCat",
  feed."salesPersonCode1",
  feed."salesPersonCode2",
  feed."commissionPerc1",
  feed."commissionPerc2",
  feed."factorCode",
  feed."currencyCode",
  feed."glCode",
  feed."createdTime",
  feed."createdUser",
  feed."modTime",
  feed."modUser"
from archive.external_customer_feed_6998 feed
left join archive.external_customer_prod_6998 previous using ("customerCode");

-- Owner-mediated views preserve reader access without granting access to the
-- private feed. Copy relation-level SELECT grants only. Archived rows and the
-- internal projection are private, including on environments with defaults.
revoke all on archive.external_customer_feed_6998 from public, anon, authenticated, service_role;
revoke all on core."externalCustomer", dflow_prod."externalCustomer" from public, anon, authenticated, service_role;

do $privileges$
declare
  mapping record;
  permission record;
  recipient text;
begin
  for mapping in
    select * from (values
      ('archive.external_customer_core_6998'::regclass, 'core."externalCustomer"'::regclass),
      ('archive.external_customer_prod_6998'::regclass, 'dflow_prod."externalCustomer"'::regclass)
    ) as relations(archived, reader)
  loop
    if exists (
      select 1 from pg_attribute
      where attrelid = mapping.archived and attnum > 0 and attacl is not null
    ) then
      raise exception 'D1: unexpected column grants on archived customer relation';
    end if;

    for permission in
      select distinct acl.grantee, role.rolname
      from pg_class relation
      cross join lateral aclexplode(relation.relacl) acl
      left join pg_roles role on role.oid = acl.grantee
      where relation.oid = mapping.reader and acl.grantee <> relation.relowner
    loop
      recipient := case when permission.grantee = 0 then 'public' else quote_ident(permission.rolname) end;
      execute format('revoke all on table %s from %s', mapping.reader, recipient);
    end loop;

    for permission in
      select acl.grantee, role.rolname, bool_or(acl.privilege_type = 'SELECT') as can_read
      from pg_class relation
      cross join lateral aclexplode(relation.relacl) acl
      left join pg_roles role on role.oid = acl.grantee
      where relation.oid = mapping.archived and acl.grantee <> relation.relowner
      group by acl.grantee, role.rolname
    loop
      recipient := case when permission.grantee = 0 then 'public' else quote_ident(permission.rolname) end;
      if permission.can_read then
        execute format('grant select on table %s to %s', mapping.reader, recipient);
      end if;
      execute format('revoke all on table %s from %s', mapping.archived, recipient);
    end loop;
  end loop;
end;
$privileges$;

comment on view core."externalCustomer" is
  'DesignFlow read-only ERP customer contract over the current ColdLion Edge Home customer feed.';
comment on view dflow_prod."externalCustomer" is
  'Production DesignFlow read-only ERP customer contract over the current ColdLion Edge Home customer feed.';

commit;
