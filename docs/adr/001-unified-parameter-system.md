# ADR-001: Unified Parameter Passing System

**Date**: 2025-09
**Status**: Accepted

## Problem

install.sh and xrf use different parameter formats. Environment variables don't work in pipes.

## Decision

Completely unify to command-line parameters, remove mixed environment variable mode.

## Rationale

- **Pipe-friendly**: `curl | bash -s -- --domain x.com` works normally
- **Zero maintenance burden**: Single parameter definition point, no compatibility baggage
- **Interface consistency**: Different entry points use the same parameters
