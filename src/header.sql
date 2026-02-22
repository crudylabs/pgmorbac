-- =============================================================================
-- pg_morbac Extension
-- =============================================================================
-- Multi-OrBAC: Organization-Based Access Control with Multi-Organization Support
-- Based on the CNRS research paper on Multi-OrBAC model
--
-- This extension implements:
-- - Role-Based Access Control (RBAC) with organizational scoping
-- - Hierarchical organizations, roles, activities, and views
-- - Permission, Prohibition, Obligation, and Recommendation deontic modalities
-- - Temporal constraints on rules
-- - Contextual access control
-- - Role delegation with time bounds
-- =============================================================================

-- Create the morbac schema
CREATE SCHEMA IF NOT EXISTS morbac;
