Describe "Internal Tests"
    Include ./spec/support/internal.sh

    It "Forwards options"
        When call primer alpine -v error -s test --test:variable myTest --test:test variable
        The output should equal myTest
        The error should match pattern "*"; # First time we use Alpine might lead to download info from docker command.
    End

    It "Detects root"
        When call primer alpine -v error -s test --test:test os_sudo
        The output should equal ""
    End

    It "Detect platform"
        When call primer alpine -v error -s test --test:test os_platform
        The output should equal x86_64
    End

    It "Detect distribution"
        When call primer alpine -v error -s test --test:test os_distribution
        The output should equal alpine
    End

    It "Detect Version"
        When call primer alpine:3.11.5 -v error -s test --test:test os_version
        The output should equal 3.11.5
        The error should match pattern "*"
    End

    It "Detect running in container"
        When call primer alpine -v error -s test --test:test os_container
        The output should equal 1
    End

    It "Installs dependencies"
        When call primer alpine -v error -s test --test:test os_curl
        The output should match pattern "Usage: curl*"
    End

    It "Locate correctly"
        When call primer alpine -v error -s test --test:test utils_locate
        The output should include test.sh
    End

    It "Finds local interface"
        When call primer alpine -v error -s test --test:test net_interfaces
        The output should start with "lo"
    End

    It "Finds MAC addresses"
        When call primer alpine -v error -s test --test:test net_macaddr
        The output should include "02:42:ac:11"
    End

    It "Finds main address"
        When call primer alpine -v error -s test --test:test net_primary_interface
        The output should start with "eth"
    End
End