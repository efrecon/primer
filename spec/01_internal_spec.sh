Describe "Internal Tests"
    Include ./spec/support/internal.sh

    It "Forwards options"
        When call primer alpine -v error -s test --test:variable myTest --test:test variable
        The output should equal myTest
    End

    It "Detects root"
        When call primer alpine -v error -s test --test:test sudo
        The output should equal ""
    End

    It "Detect platform"
        When call primer alpine -v error -s test --test:test platform
        The output should equal x86_64
    End

    It "Detect distribution"
        When call primer alpine -v error -s test --test:test distribution
        The output should equal alpine
    End

    It "Locate correctly"
        When call primer alpine -v error -s test --test:test locate
        The output should include test.sh
    End
End