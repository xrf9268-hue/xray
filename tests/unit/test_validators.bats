#!/usr/bin/env bats
# Unit tests for validators module (lib/validators.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source validators module
  source "${PROJECT_ROOT}/lib/validators.sh" 2>/dev/null || true
}

teardown() {
  cleanup_test_env
}

# Domain validation tests
@test "validators::domain - accepts valid domain" {
  run validators::domain "example.com"
  [ "$status" -eq 0 ]
}

@test "validators::domain - accepts subdomain" {
  run validators::domain "sub.example.com"
  [ "$status" -eq 0 ]
}

@test "validators::domain - accepts deep subdomain" {
  run validators::domain "deep.sub.example.com"
  [ "$status" -eq 0 ]
}

@test "validators::domain - accepts domain with hyphen" {
  run validators::domain "my-site.example.com"
  [ "$status" -eq 0 ]
}

@test "validators::domain - accepts numeric TLD" {
  run validators::domain "example.co.uk"
  [ "$status" -eq 0 ]
}

@test "validators::domain - rejects empty domain" {
  run validators::domain ""
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects localhost" {
  run validators::domain "localhost"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects .local domain" {
  run validators::domain "test.local"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects 127.x.x.x" {
  run validators::domain "127.0.0.1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects 10.x.x.x" {
  run validators::domain "10.0.0.1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects 192.168.x.x" {
  run validators::domain "192.168.1.1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects 172.16-31.x.x" {
  run validators::domain "172.16.0.1"
  [ "$status" -ne 0 ]

  run validators::domain "172.20.0.1"
  [ "$status" -ne 0 ]

  run validators::domain "172.31.0.1"
  [ "$status" -ne 0 ]
}

# RFC 3927 link-local addresses
@test "validators::domain - rejects 169.254.0.0/16 link-local (RFC 3927)" {
  run validators::domain "169.254.10.1"
  [ "$status" -ne 0 ]

  run validators::domain "169.254.0.1"
  [ "$status" -ne 0 ]

  run validators::domain "169.254.255.254"
  [ "$status" -ne 0 ]
}

# RFC 6761 special-use TLDs
@test "validators::domain - rejects .test TLD (RFC 6761)" {
  run validators::domain "example.test"
  [ "$status" -ne 0 ]

  run validators::domain "my-app.test"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects .invalid TLD (RFC 6761)" {
  run validators::domain "foo.invalid"
  [ "$status" -ne 0 ]

  run validators::domain "test.invalid"
  [ "$status" -ne 0 ]
}

# IPv6 loopback
@test "validators::domain - rejects ::1 (IPv6 loopback)" {
  run validators::domain "::1"
  [ "$status" -ne 0 ]
}

# IPv6 unique local addresses (RFC 4193)
@test "validators::domain - rejects fc00::/7 (IPv6 ULA - RFC 4193)" {
  run validators::domain "fc00:1234:5678::1"
  [ "$status" -ne 0 ]

  run validators::domain "fd00:abcd:ef01::1"
  [ "$status" -ne 0 ]

  run validators::domain "fcff:ffff:ffff::1"
  [ "$status" -ne 0 ]

  run validators::domain "fdff:ffff:ffff::1"
  [ "$status" -ne 0 ]
}

# IPv6 link-local (RFC 4291)
@test "validators::domain - rejects fe80::/10 (IPv6 link-local - RFC 4291)" {
  run validators::domain "fe80::1"
  [ "$status" -ne 0 ]

  run validators::domain "fe80:0000:0000:0000:0202:b3ff:fe1e:8329"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects domain starting with hyphen" {
  run validators::domain "-invalid.com"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects domain ending with hyphen" {
  run validators::domain "invalid-.com"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects domain with double dot" {
  run validators::domain "invalid..com"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects domain with underscore" {
  run validators::domain "invalid_domain.com"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects domain exceeding 253 characters" {
  # DNS spec: total length must be <= 253
  local long_domain
  long_domain="$(printf 'a%.0s' {1..250}).com"  # 254 chars total
  run validators::domain "${long_domain}"
  [ "$status" -ne 0 ]
}

@test "validators::domain - accepts domain at 253 character limit" {
  # Create a valid domain exactly 253 chars with valid label lengths
  # 4 labels of 63 chars each = 252 chars + 3 dots = 255, so use 62+63+63+63 = 251 + 3 = 254
  # Use 61+63+63+63 = 250 + 3 = 253 chars total
  local max_domain
  max_domain="$(printf 'a%.0s' {1..61}).$(printf 'b%.0s' {1..63}).$(printf 'c%.0s' {1..63}).$(printf 'd%.0s' {1..63})"

  # Verify it's exactly 253 chars
  [[ ${#max_domain} -eq 253 ]] || skip "test domain not 253 chars: ${#max_domain}"

  run validators::domain "${max_domain}"
  [ "$status" -eq 0 ]
}

@test "validators::domain - rejects label exceeding 63 characters" {
  # DNS spec: each label must be <= 63 chars
  local long_label
  long_label="$(printf 'a%.0s' {1..64}).com"
  run validators::domain "${long_label}"
  [ "$status" -ne 0 ]
}

@test "validators::domain - accepts label at 63 character limit" {
  local max_label
  max_label="$(printf 'a%.0s' {1..63}).com"
  run validators::domain "${max_label}"
  [ "$status" -eq 0 ]
}

# Port validation tests
@test "validators::port - accepts valid port 80" {
  run validators::port "80"
  [ "$status" -eq 0 ]
}

@test "validators::port - accepts valid port 443" {
  run validators::port "443"
  [ "$status" -eq 0 ]
}

@test "validators::port - accepts valid port 8443" {
  run validators::port "8443"
  [ "$status" -eq 0 ]
}

@test "validators::port - accepts port 1 (minimum)" {
  run validators::port "1"
  [ "$status" -eq 0 ]
}

@test "validators::port - accepts port 65535 (maximum)" {
  run validators::port "65535"
  [ "$status" -eq 0 ]
}

@test "validators::port - rejects port 0" {
  run validators::port "0"
  [ "$status" -ne 0 ]
}

@test "validators::port - rejects port 65536" {
  run validators::port "65536"
  [ "$status" -ne 0 ]
}

@test "validators::port - rejects negative port" {
  run validators::port "-1"
  [ "$status" -ne 0 ]
}

@test "validators::port - rejects non-numeric port" {
  run validators::port "abc"
  [ "$status" -ne 0 ]
}

@test "validators::port - rejects empty port" {
  run validators::port ""
  [ "$status" -ne 0 ]
}

# UUID validation tests
@test "validators::uuid - accepts valid UUIDv4" {
  run validators::uuid "550e8400-e29b-41d4-a716-446655440000"
  [ "$status" -eq 0 ]
}

@test "validators::uuid - accepts lowercase UUID" {
  run validators::uuid "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  [ "$status" -eq 0 ]
}

@test "validators::uuid - accepts uppercase UUID" {
  run validators::uuid "F47AC10B-58CC-4372-A567-0E02B2C3D479"
  [ "$status" -eq 0 ]
}

@test "validators::uuid - rejects invalid UUID format" {
  run validators::uuid "not-a-uuid"
  [ "$status" -ne 0 ]
}

@test "validators::uuid - rejects UUID with wrong segment lengths" {
  run validators::uuid "550e8400-e29b-41d4-a716-44665544000"  # Missing one char
  [ "$status" -ne 0 ]
}

@test "validators::uuid - rejects empty UUID" {
  run validators::uuid ""
  [ "$status" -ne 0 ]
}

# shortId validation tests
@test "validators::shortid - accepts valid shortid" {
  run validators::shortid "0123456789abcdef"
  [ "$status" -eq 0 ]
}

@test "validators::shortid - accepts uppercase hex" {
  run validators::shortid "0123456789ABCDEF"
  [ "$status" -eq 0 ]
}

@test "validators::shortid - accepts mixed case hex" {
  run validators::shortid "0123456789AbCdEf"
  [ "$status" -eq 0 ]
}

@test "validators::shortid - accepts empty string" {
  # Empty shortId is valid (part of the pool)
  run validators::shortid ""
  [ "$status" -eq 0 ]
}

@test "validators::shortid - accepts 2 character shortid" {
  run validators::shortid "ab"
  [ "$status" -eq 0 ]
}

@test "validators::shortid - accepts 16 character shortid (max)" {
  run validators::shortid "0123456789abcdef"
  [ "$status" -eq 0 ]
}

@test "validators::shortid - rejects shortid exceeding 16 characters" {
  run validators::shortid "0123456789abcdef0"  # 17 chars
  [ "$status" -ne 0 ]
}

@test "validators::shortid - rejects odd-length shortid" {
  run validators::shortid "abc"  # 3 chars (odd)
  [ "$status" -ne 0 ]
}

@test "validators::shortid - rejects non-hex characters" {
  run validators::shortid "ghij"
  [ "$status" -ne 0 ]
}

@test "validators::shortid - rejects shortid with spaces" {
  run validators::shortid "ab cd"
  [ "$status" -ne 0 ]
}

@test "validators::hostname - accepts domain" {
  run validators::hostname "example.com"
  [ "$status" -eq 0 ]
}

@test "validators::hostname - rejects empty" {
  run validators::hostname ""
  [ "$status" -ne 0 ]
}

@test "validators::hostname - rejects unsafe characters" {
  run validators::hostname "bad\"host"
  [ "$status" -ne 0 ]
}

@test "validators::hostname - rejects invalid domain" {
  run validators::hostname "bad_host"
  [ "$status" -ne 0 ]
}

# Security tests - RFC 3927 link-local addresses
@test "validators::domain - rejects RFC 3927 link-local start (169.254.0.1)" {
  run validators::domain "169.254.0.1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects RFC 3927 link-local end (169.254.255.255)" {
  run validators::domain "169.254.255.255"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects RFC 3927 link-local mid-range" {
  run validators::domain "169.254.100.50"
  [ "$status" -ne 0 ]
}

# Security tests - RFC 6761 special-use domain names
@test "validators::domain - rejects RFC 6761 .test TLD" {
  run validators::domain "example.test"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects RFC 6761 .invalid TLD" {
  run validators::domain "domain.invalid"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects RFC 6761 subdomain.test" {
  run validators::domain "sub.example.test"
  [ "$status" -ne 0 ]
}

# Security tests - IPv6 private addresses
@test "validators::domain - rejects IPv6 loopback (::1)" {
  run validators::domain "::1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects IPv6 unique local fc00::" {
  run validators::domain "fc00::1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects IPv6 unique local fd00::" {
  run validators::domain "fd00::1"
  [ "$status" -ne 0 ]
}

@test "validators::domain - rejects IPv6 link-local fe80::" {
  run validators::domain "fe80::1"
  [ "$status" -ne 0 ]
}

# Positive tests - ensure we don't over-reject
@test "validators::domain - accepts valid public domain" {
  run validators::domain "www.google.com"
  [ "$status" -eq 0 ]
}

@test "validators::domain - accepts domain with numbers" {
  run validators::domain "server123.example.com"
  [ "$status" -eq 0 ]
}
