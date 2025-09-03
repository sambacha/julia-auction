# Security Guide

## Overview

This guide covers security best practices for deploying and operating the Julia Auction System in production environments.

## Authentication & Authorization

### API Key Management

```julia
# src/security/auth.jl
using SHA
using Base64

struct APIKey
    key::String
    permissions::Set{Symbol}
    rate_limit::Int
    created_at::DateTime
    expires_at::Union{DateTime, Nothing}
end

function validate_api_key(key::String)::Union{APIKey, Nothing}
    # Hash the key for comparison
    key_hash = bytes2hex(sha256(key))
    
    # Look up in secure storage
    stored_key = get_from_secure_storage(key_hash)
    
    if isnothing(stored_key)
        return nothing
    end
    
    # Check expiration
    if !isnothing(stored_key.expires_at) && now() > stored_key.expires_at
        return nothing
    end
    
    return stored_key
end

function create_api_key(permissions::Set{Symbol}, expires_days::Int = 90)
    # Generate secure random key
    key_bytes = rand(UInt8, 32)
    key = base64encode(key_bytes)
    
    api_key = APIKey(
        key,
        permissions,
        1000,  # Default rate limit
        now(),
        now() + Day(expires_days)
    )
    
    # Store hashed version
    key_hash = bytes2hex(sha256(key))
    store_in_secure_storage(key_hash, api_key)
    
    return key
end
```

### JWT Authentication

```julia
using JSON
using JSONWebTokens

struct JWTConfig
    secret::String
    issuer::String
    audience::String
    expiration_minutes::Int
end

function generate_jwt(user_id::String, config::JWTConfig)
    payload = Dict(
        "sub" => user_id,
        "iss" => config.issuer,
        "aud" => config.audience,
        "iat" => round(Int, datetime2unix(now())),
        "exp" => round(Int, datetime2unix(now() + Minute(config.expiration_minutes))),
        "jti" => string(uuid4())
    )
    
    return encode(HS256(config.secret), payload)
end

function verify_jwt(token::String, config::JWTConfig)
    try
        claims = decode(HS256(config.secret), token)
        
        # Verify claims
        if claims["iss"] != config.issuer || claims["aud"] != config.audience
            return nothing
        end
        
        # Check expiration
        if claims["exp"] < round(Int, datetime2unix(now()))
            return nothing
        end
        
        return claims
    catch e
        @error "JWT verification failed" error=e
        return nothing
    end
end
```

### Role-Based Access Control (RBAC)

```julia
# Define roles and permissions
const ROLES = Dict(
    :admin => Set([:create, :read, :update, :delete, :admin]),
    :trader => Set([:create_bid, :read, :cancel_bid]),
    :viewer => Set([:read]),
    :operator => Set([:create, :read, :update, :admin_read])
)

struct User
    id::String
    roles::Set{Symbol}
end

function has_permission(user::User, permission::Symbol)::Bool
    for role in user.roles
        if permission in ROLES[role]
            return true
        end
    end
    return false
end

# Middleware for permission checking
function require_permission(permission::Symbol)
    return function(handler)
        return function(request)
            user = get_user_from_request(request)
            
            if isnothing(user) || !has_permission(user, permission)
                return HTTP.Response(403, "Forbidden")
            end
            
            return handler(request)
        end
    end
end
```

## Data Protection

### Encryption at Rest

```julia
using AES

struct EncryptionConfig
    key::Vector{UInt8}
    algorithm::Symbol  # :aes256_gcm, :chacha20_poly1305
end

function encrypt_sensitive_data(data::String, config::EncryptionConfig)
    # Generate random IV
    iv = rand(UInt8, 12)
    
    # Encrypt data
    cipher = AES_GCM(config.key)
    ciphertext, tag = encrypt(cipher, iv, data)
    
    # Combine IV + tag + ciphertext for storage
    return vcat(iv, tag, ciphertext)
end

function decrypt_sensitive_data(encrypted::Vector{UInt8}, config::EncryptionConfig)
    # Extract components
    iv = encrypted[1:12]
    tag = encrypted[13:28]
    ciphertext = encrypted[29:end]
    
    # Decrypt
    cipher = AES_GCM(config.key)
    plaintext = decrypt(cipher, iv, ciphertext, tag)
    
    return String(plaintext)
end

# Example: Encrypting bid data
function store_bid_securely(bid::Bid, encryption_config::EncryptionConfig)
    sensitive_data = JSON.json(Dict(
        "bidder" => bid.bidder,
        "price" => bid.price,
        "quantity" => bid.quantity
    ))
    
    encrypted = encrypt_sensitive_data(sensitive_data, encryption_config)
    
    # Store encrypted data
    store_in_database(bid.id, encrypted)
end
```

### TLS Configuration

```julia
using MbedTLS
using HTTP

function create_secure_server(port::Int, cert_path::String, key_path::String)
    # Load certificate and key
    cert = MbedTLS.crt_parse_file(cert_path)
    key = MbedTLS.parse_keyfile(key_path)
    
    # Configure TLS
    tls_config = MbedTLS.SSLConfig(
        cert,
        key,
        min_version = MbedTLS.MBEDTLS_SSL_VERSION_TLS1_2,
        ciphersuites = [
            MbedTLS.MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            MbedTLS.MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        ]
    )
    
    # Start HTTPS server
    HTTP.serve(port=port, sslconfig=tls_config) do request
        handle_request(request)
    end
end
```

## Input Validation & Sanitization

### Request Validation

```julia
struct ValidationRule
    field::Symbol
    type::Type
    min::Union{Number, Nothing}
    max::Union{Number, Nothing}
    pattern::Union{Regex, Nothing}
end

function validate_request(data::Dict, rules::Vector{ValidationRule})
    errors = String[]
    
    for rule in rules
        if !haskey(data, String(rule.field))
            push!(errors, "Missing required field: $(rule.field)")
            continue
        end
        
        value = data[String(rule.field)]
        
        # Type validation
        if !isa(value, rule.type)
            push!(errors, "Invalid type for $(rule.field)")
            continue
        end
        
        # Range validation
        if !isnothing(rule.min) && value < rule.min
            push!(errors, "$(rule.field) must be >= $(rule.min)")
        end
        
        if !isnothing(rule.max) && value > rule.max
            push!(errors, "$(rule.field) must be <= $(rule.max)")
        end
        
        # Pattern validation
        if !isnothing(rule.pattern) && isa(value, String)
            if !occursin(rule.pattern, value)
                push!(errors, "$(rule.field) format invalid")
            end
        end
    end
    
    return errors
end

# Example: Validate bid submission
const BID_VALIDATION_RULES = [
    ValidationRule(:quantity, Float64, 0.0, 1000000.0, nothing),
    ValidationRule(:price, Float64, 0.0, 1000000.0, nothing),
    ValidationRule(:auction_id, String, nothing, nothing, r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
]

function validate_bid(bid_data::Dict)
    errors = validate_request(bid_data, BID_VALIDATION_RULES)
    
    if !isempty(errors)
        throw(ValidationError(errors))
    end
end
```

### SQL Injection Prevention

```julia
using LibPQ

# NEVER do this - vulnerable to SQL injection
function unsafe_query(conn, user_input::String)
    query = "SELECT * FROM bids WHERE bidder = '$user_input'"  # DON'T DO THIS
    return execute(conn, query)
end

# ALWAYS use parameterized queries
function safe_query(conn, user_input::String)
    query = "SELECT * FROM bids WHERE bidder = \$1"
    return execute(conn, query, [user_input])
end

# Prepared statements for frequently used queries
function prepare_common_queries(conn)
    prepare(conn, "get_bid", "SELECT * FROM bids WHERE bid_id = \$1")
    prepare(conn, "insert_bid", "INSERT INTO bids (bid_id, bidder, quantity, price) VALUES (\$1, \$2, \$3, \$4)")
    prepare(conn, "update_bid_status", "UPDATE bids SET status = \$1 WHERE bid_id = \$2")
end

function execute_prepared(conn, stmt_name::String, params::Vector)
    return execute(conn, stmt_name, params)
end
```

## Rate Limiting & DDoS Protection

### Rate Limiter Implementation

```julia
using DataStructures

mutable struct RateLimiter
    requests::DefaultDict{String, CircularBuffer{DateTime}}
    limits::Dict{String, Int}
    window_seconds::Int
end

function RateLimiter(window_seconds::Int = 60)
    return RateLimiter(
        DefaultDict{String, CircularBuffer{DateTime}}(() -> CircularBuffer{DateTime}(1000)),
        Dict{String, Int}(),
        window_seconds
    )
end

function is_rate_limited(limiter::RateLimiter, client_id::String, limit::Int)::Bool
    current_time = now()
    window_start = current_time - Second(limiter.window_seconds)
    
    # Get client's request history
    history = limiter.requests[client_id]
    
    # Remove old requests outside window
    while !isempty(history) && first(history) < window_start
        popfirst!(history)
    end
    
    # Check if limit exceeded
    if length(history) >= limit
        return true
    end
    
    # Record new request
    push!(history, current_time)
    return false
end

# Middleware for rate limiting
function rate_limit_middleware(limiter::RateLimiter, limit::Int)
    return function(handler)
        return function(request)
            client_id = get_client_id(request)  # From IP or API key
            
            if is_rate_limited(limiter, client_id, limit)
                return HTTP.Response(429, "Rate limit exceeded")
            end
            
            return handler(request)
        end
    end
end
```

### Circuit Breaker for External Services

```julia
mutable struct CircuitBreaker
    failure_count::Int
    last_failure_time::Union{DateTime, Nothing}
    state::Symbol  # :closed, :open, :half_open
    failure_threshold::Int
    recovery_timeout::Second
    success_threshold::Int
    consecutive_successes::Int
end

function call_with_circuit_breaker(breaker::CircuitBreaker, f::Function, args...)
    if breaker.state == :open
        # Check if recovery timeout has passed
        if !isnothing(breaker.last_failure_time) && 
           now() - breaker.last_failure_time > breaker.recovery_timeout
            breaker.state = :half_open
            breaker.consecutive_successes = 0
        else
            throw(CircuitBreakerOpenError("Circuit breaker is open"))
        end
    end
    
    try
        result = f(args...)
        
        # Record success
        if breaker.state == :half_open
            breaker.consecutive_successes += 1
            if breaker.consecutive_successes >= breaker.success_threshold
                breaker.state = :closed
                breaker.failure_count = 0
            end
        end
        
        return result
    catch e
        # Record failure
        breaker.failure_count += 1
        breaker.last_failure_time = now()
        
        if breaker.failure_count >= breaker.failure_threshold
            breaker.state = :open
        end
        
        rethrow(e)
    end
end
```

## Security Headers

```julia
function add_security_headers(response::HTTP.Response)
    headers = [
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "X-XSS-Protection" => "1; mode=block",
        "Strict-Transport-Security" => "max-age=31536000; includeSubDomains",
        "Content-Security-Policy" => "default-src 'self'",
        "Referrer-Policy" => "strict-origin-when-cross-origin",
        "Permissions-Policy" => "geolocation=(), microphone=(), camera=()"
    ]
    
    for (key, value) in headers
        HTTP.setheader(response, key => value)
    end
    
    return response
end

# Apply to all responses
function security_headers_middleware(handler)
    return function(request)
        response = handler(request)
        return add_security_headers(response)
    end
end
```

## Audit Logging

```julia
struct AuditLog
    timestamp::DateTime
    user_id::Union{String, Nothing}
    ip_address::String
    action::String
    resource::String
    result::Symbol  # :success, :failure, :error
    details::Dict{String, Any}
end

function log_audit_event(event::AuditLog)
    # Format for structured logging
    log_entry = Dict(
        "timestamp" => event.timestamp,
        "user_id" => event.user_id,
        "ip_address" => event.ip_address,
        "action" => event.action,
        "resource" => event.resource,
        "result" => event.result,
        "details" => event.details
    )
    
    # Write to secure audit log
    write_to_audit_log(JSON.json(log_entry))
    
    # Alert on suspicious activity
    if event.result == :failure && is_suspicious(event)
        send_security_alert(event)
    end
end

function is_suspicious(event::AuditLog)::Bool
    # Check for patterns indicating potential attacks
    suspicious_patterns = [
        r".*(\.\./|\.\.\\).*",  # Path traversal
        r".*(union|select|drop|insert|update|delete).*",  # SQL injection attempts
        r".*<script.*",  # XSS attempts
    ]
    
    details_str = JSON.json(event.details)
    for pattern in suspicious_patterns
        if occursin(pattern, details_str, ignorecase=true)
            return true
        end
    end
    
    return false
end
```

## Secure Configuration Management

```julia
using TOML

struct SecureConfig
    data::Dict
    encrypted_fields::Set{String}
    encryption_key::Vector{UInt8}
end

function load_secure_config(path::String, key::Vector{UInt8})
    raw_config = TOML.parsefile(path)
    
    encrypted_fields = Set(get(raw_config, "_encrypted_fields", String[]))
    
    # Decrypt sensitive fields
    for field in encrypted_fields
        if haskey(raw_config, field)
            encrypted_value = base64decode(raw_config[field])
            raw_config[field] = decrypt_sensitive_data(encrypted_value, 
                                                      EncryptionConfig(key, :aes256_gcm))
        end
    end
    
    return SecureConfig(raw_config, encrypted_fields, key)
end

# Environment variable validation
function validate_environment()
    required_vars = [
        "AUCTION_ENCRYPTION_KEY",
        "AUCTION_JWT_SECRET",
        "AUCTION_DATABASE_URL"
    ]
    
    missing = String[]
    for var in required_vars
        if !haskey(ENV, var)
            push!(missing, var)
        end
    end
    
    if !isempty(missing)
        error("Missing required environment variables: $(join(missing, ", "))")
    end
end
```

## Vulnerability Scanning

### Dependency Checking

```julia
function check_dependencies()
    # Parse Project.toml
    project = TOML.parsefile("Project.toml")
    
    vulnerabilities = []
    
    for (pkg, version) in project["deps"]
        # Check against vulnerability database
        vulns = check_package_vulnerabilities(pkg, version)
        
        if !isempty(vulns)
            push!(vulnerabilities, (pkg, version, vulns))
        end
    end
    
    if !isempty(vulnerabilities)
        @warn "Security vulnerabilities found in dependencies" vulnerabilities
    end
    
    return vulnerabilities
end
```

## Incident Response

### Emergency Shutdown

```julia
function emergency_shutdown(reason::String)
    @error "EMERGENCY SHUTDOWN INITIATED" reason=reason
    
    # 1. Stop accepting new requests
    set_maintenance_mode(true)
    
    # 2. Log the incident
    log_audit_event(AuditLog(
        now(),
        nothing,
        "system",
        "emergency_shutdown",
        "system",
        :success,
        Dict("reason" => reason)
    ))
    
    # 3. Notify administrators
    send_emergency_alert(reason)
    
    # 4. Gracefully shut down services
    shutdown_services()
    
    exit(1)
end
```

## Security Checklist

### Pre-Deployment

- [ ] All dependencies updated to latest secure versions
- [ ] Security audit performed on code
- [ ] Penetration testing completed
- [ ] TLS certificates valid and properly configured
- [ ] Secrets stored in secure vault (not in code)
- [ ] Rate limiting configured
- [ ] Input validation implemented for all endpoints
- [ ] Security headers configured
- [ ] Audit logging enabled
- [ ] Backup and recovery procedures tested

### Runtime Monitoring

- [ ] Monitor authentication failures
- [ ] Track rate limit violations
- [ ] Review audit logs regularly
- [ ] Monitor for suspicious patterns
- [ ] Check certificate expiration
- [ ] Verify security patches applied
- [ ] Test incident response procedures
- [ ] Review access control lists
- [ ] Validate encryption keys rotated
- [ ] Check for unauthorized access attempts

## Next Steps

- [Deployment Guide](deployment.md) - Production deployment
- [Monitoring Guide](monitoring.md) - Security monitoring
- [Troubleshooting](troubleshooting.md) - Security issues