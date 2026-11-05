# DesignFlow table index and naming standard (2026-11-05)

Every DesignFlow production table (`dflow_prod`, 134 tables, read live on 2026-11-05),
grouped by business area. Each group has one prefix.

**Naming standard (new tables only):** a new DesignFlow table takes its group's prefix,
in lowercase snake_case, for example `rfq_vendor_quote` or `sample_label`. Existing tables
keep their names. This index links each old name to its group, so old and new tables in
one area are found together. A new table outside every group needs a new group added
here first.

The "Permanent home" column lists the same-name table in `plm` / `core` / `app`, or says it
stays in `dflow_prod`. The move order is in
[designflow-dflow-prod-move-groups-20261105.md](designflow-dflow-prod-move-groups-20261105.md).

## Grid layouts — prefix for new tables: `grid_`

| Table today | Permanent home |
|---|---|
| GridAccessLevel | plm.GridAccessLevel |
| GridChildrenLayout | plm.GridChildrenLayout |
| GridChildrenLayoutOrder | plm.GridChildrenLayoutOrder |
| GridLayout | plm.GridLayout |
| GridViewState | plm.GridViewState |
| grid_cell_notes | plm.grid_cell_notes |
| tracking_grid_archive | stays in dflow_prod |

## User-defined fields — prefix for new tables: `udf_`

| Table today | Permanent home |
|---|---|
| UDFComponent | plm.UDFComponent |
| UDFElement | plm.UDFElement |
| UDFElementType | plm.UDFElementType |
| UDFGroup | plm.UDFGroup |
| UDFQuery | plm.UDFQuery |
| UDFTable | plm.UDFTable |

## Standardized product — prefix for new tables: `std_`

| Table today | Permanent home |
|---|---|
| StandardizedDetail | plm.StandardizedDetail |
| StandardizedGroup | plm.StandardizedGroup |
| StandardizedProductElement | plm.StandardizedProductElement |
| StandardizedProductElementValue | plm.StandardizedProductElementValue |
| StandardizedProductType | plm.StandardizedProductType |
| StandardizedSize | plm.StandardizedSize |
| StandardizedVendor | plm.StandardizedVendor |
| StandardizedVersion | plm.StandardizedVersion |

## Samples — prefix for new tables: `sample_`

| Table today | Permanent home |
|---|---|
| sample | plm.sample |
| sample_approval_event | stays in dflow_prod |
| sample_attachment | plm.sample_attachment |
| sample_box | plm.sample_box |
| sample_carrier | stays in dflow_prod |
| sample_comments | plm.sample_comments |
| sample_creation_batch | stays in dflow_prod |
| sample_event | plm.sample_event |
| sample_factory_group | plm.sample_factory_group |
| sample_factory_visit | stays in dflow_prod |
| sample_factory_visit_event | stays in dflow_prod |
| sample_import_job | stays in dflow_prod |
| sample_import_row | stays in dflow_prod |
| sample_inventory_balance | stays in dflow_prod |
| sample_movement | stays in dflow_prod |
| sample_path_revision | stays in dflow_prod |
| sample_piece_lineage | stays in dflow_prod |
| sample_remote_request | stays in dflow_prod |
| sample_remote_request_history | stays in dflow_prod |
| sample_remote_request_item | stays in dflow_prod |
| sample_reservation | stays in dflow_prod |
| sample_shipment | stays in dflow_prod |
| sample_shipment_item | plm.sample_shipment_item |
| sample_shipment_line | stays in dflow_prod |
| sample_shipment_notice | stays in dflow_prod |
| sample_shipment_notice_recipient | stays in dflow_prod |
| sample_stop_closeout | stays in dflow_prod |
| sample_workflow | stays in dflow_prod |

## RFQ — prefix for new tables: `rfq_`

| Table today | Permanent home |
|---|---|
| RFQContainer | plm.RFQContainer |
| RFQGroup | plm.RFQGroup |
| RFQItem | plm.RFQItem |
| RFQItemDivision | plm.RFQItemDivision |
| RFQItemStatus | plm.RFQItemStatus |
| RFQStep | plm.RFQStep |
| RFQVendor | plm.RFQVendor |
| RFQWhse | plm.RFQWhse |

## Items — prefix for new tables: `item_`

| Table today | Permanent home |
|---|---|
| ProductNickname | plm.ProductNickname |
| itemAttachment | plm.itemAttachment |
| itemDepth | plm.itemDepth |
| itemDetail | plm.itemDetail |
| itemHeader | plm.itemHeader |
| itemLicenseImage | plm.itemLicenseImage |
| itemSize | plm.itemSize |
| itemType | plm.itemType |
| item_character_associations | plm.item_character_associations |
| item_customer_selling | stays in dflow_prod |
| item_prod_order_detail_associations | plm.item_prod_order_detail_associations |
| item_user_assignment | plm.item_user_assignment |
| item_workflow_action | plm.item_workflow_action |
| productUserAssignment | plm.productUserAssignment |

## Production orders — prefix for new tables: `po_`

| Table today | Permanent home |
|---|---|
| ContainerHeader | plm.ContainerHeader |
| FOBCountry | plm.FOBCountry |
| FactoryTime | plm.FactoryTime |
| FactoryTimes | plm.FactoryTimes |
| OrderLeadTime | plm.OrderLeadTime |
| ProdOrderDetail | plm.ProdOrderDetail |
| ProdOrderHeader | plm.ProdOrderHeader |
| ProdPaymentTerms | plm.ProdPaymentTerms |
| ProdShipmentTransitTime | plm.ProdShipmentTransitTime |
| ShippingPort | plm.ShippingPort |
| deliveryLocation | plm.deliveryLocation |
| prod_order_milestone_schedule | plm.prod_order_milestone_schedule |
| product_type_factory_time | plm.product_type_factory_time |

## Licensing — prefix for new tables: `lic_`

| Table today | Permanent home |
|---|---|
| LicenseFeedBacks | plm.LicenseFeedBacks |
| LicensingTime | plm.LicensingTime |
| LicensingTimes | plm.LicensingTimes |
| groups | plm.groups |
| licenseList | core.licenseList |
| licensingFeedbackReply | plm.licensingFeedbackReply |
| licensingMilestone | plm.licensingMilestone |
| licensingStatus | plm.licensingStatus |

## Merch groups and taxonomy — prefix for new tables: `merch_`

| Table today | Permanent home |
|---|---|
| SeasonCode | plm.SeasonCode |
| age_group | core.age_group |
| companyCode | plm.companyCode |
| divisionCode | plm.divisionCode |
| merchGroup | core.merchGroup |
| merchGroupHeaders | core.merchGroupHeaders |
| merchGroupMaster | core.merchGroupMaster |
| merchGroupRelations | core.merchGroupRelations |
| merchGroup_04112026 | stays in dflow_prod |
| merchGroup_pr90_bad | stays in dflow_prod |
| product_category | core.product_category |
| properties_and_characters | stays in dflow_prod |
| property_character_associations | core.property_character_associations |

## Art — prefix for new tables: `art_`

| Table today | Permanent home |
|---|---|
| art_piece | plm.art_piece |
| art_piece_attachment | plm.art_piece_attachment |
| art_types | core.art_types |
| artist_types | core.artist_types |
| artists | stays in dflow_prod |

## Design time — prefix for new tables: `design_`

| Table today | Permanent home |
|---|---|
| DesignTeamTime | plm.DesignTeamTime |
| DesignTeamTimes | plm.DesignTeamTimes |

## Users and access — prefix for new tables: `user_`

| Table today | Permanent home |
|---|---|
| AdditionalUserEmail | app.AdditionalUserEmail |
| RolePermissions | app.RolePermissions |
| Roles | stays in dflow_prod |
| UIElements | app.UIElements |
| auth_token | app.auth_token |
| quote_auth_token | app.quote_auth_token |
| user_notification | app.user_notification |
| user_roles | stays in dflow_prod |
| users | app.users |

## Vendors, factories and customers — prefix for new tables: `party_`

| Table today | Permanent home |
|---|---|
| Factory | stays in dflow_prod |
| customers | stays in dflow_prod |
| externalCustomer | core.externalCustomer |
| externalVendor | core.externalVendor |
| vendor | core.vendor |
| vendorGroup | core.vendorGroup |
| vendor_wechat_identity | stays in dflow_prod |

## Logs and settings — prefix for new tables: `log_`

| Table today | Permanent home |
|---|---|
| AuditLog | app.AuditLog |
| ai_cache_events | app.ai_cache_events |
| app_settings | app.app_settings |
| comments | stays in dflow_prod |
| email_logs | app.email_logs |
| externalApi | plm.externalApi |

