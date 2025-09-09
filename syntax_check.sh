#!/bin/bash
# Bash syntax and variable verification script

echo "=== Bash Syntax and Variable Check ==="

# Check all shell scripts for syntax errors
check_syntax() {
    local script="$1"
    echo "Checking syntax: $script"
    if bash -n "$script" 2>/dev/null; then
        echo "✓ Syntax OK"
    else
        echo "✗ Syntax Error:"
        bash -n "$script"
    fi
    echo ""
}

# Check for potential unbound variable issues
check_unbound_vars() {
    local script="$1"
    echo "Checking for potential unbound variables: $script"
    
    # Look for variable references that might be unbound
    grep -n '\$[{a-zA-Z_][a-zA-Z0-9_]*[}]*' "$script" | grep -v '${.*:-' | head -10
    echo ""
}

# Check all scripts in the new directory
for script in $(find new -name "*.sh" -type f); do
    echo "=== $script ==="
    check_syntax "$script"
    check_unbound_vars "$script"
done

echo "=== Variable Declaration Check ==="
echo "Looking for variable usage patterns..."

# Check specific problematic patterns
echo "1. FULL_VERIFY usage:"
grep -n "FULL_VERIFY" new/flash/flasher.sh

echo ""
echo "2. Variable assignments with defaults:"
grep -n "\${.*:-" new/flash/flasher.sh

echo ""
echo "3. Local variable declarations:"
grep -n "local " new/flash/flasher.sh | head -10

echo ""
echo "=== Check Complete ==="
