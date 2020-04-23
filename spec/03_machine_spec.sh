Describe "Machine"
  Describe "Alpine"
    Include ./spec/support/machine.sh

    It "installed machine"
      When call machine alpine
      The status should be success
      The output should include version
    End

    It "installed machine at precise version"
      When call machine alpine 0.16.1
      The status should be success
      The output should include 0.16.1
    End

    It "installed machine with proper sha256 sum"
      When call machine alpine 0.16.1 44a008c14549156222b314b1448c22ef255b446419fcf96570f3f288dff318a9
      The status should be success
      The output should include 0.16.1
    End

    It "installed machine with improper sha256 sum"
      When call machine alpine 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The output should match pattern '*'
      The error should include FAILED
    End
  End

  Describe "Ubuntu"
    Include ./spec/support/machine.sh

    It "installed machine"
      When call machine ubuntu
      The status should be success
      The output should include version
      The error should match pattern '*'
    End

    It "installed machine at precise version"
      When call machine ubuntu 0.16.1
      The status should be success
      The output should include 0.16.1
      The error should match pattern '*'
    End

    It "installed machine with proper sha256 sum"
      When call machine ubuntu 0.16.1 44a008c14549156222b314b1448c22ef255b446419fcf96570f3f288dff318a9
      The status should be success
      The output should include 0.16.1
      The error should match pattern '*'
    End

    It "installed machine with improper sha256 sum"
      When call machine ubuntu 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The output should match pattern '*'
      The error should include FAILED
    End
  End

  Describe "ClearLinux"
    Include ./spec/support/machine.sh

    It "installed machine"
      When call machine clearlinux
      The status should be success
      The output should include version
      The error should match pattern '*'
    End

    It "installed machine at precise version"
      When call machine clearlinux 0.16.1
      The status should be success
      The output should include 0.16.1
      The error should match pattern '*'
    End

    It "installed machine with proper sha256 sum"
      When call machine clearlinux 0.16.1 44a008c14549156222b314b1448c22ef255b446419fcf96570f3f288dff318a9
      The status should be success
      The output should include 0.16.1
      The error should match pattern '*'
    End

    It "installed machine with improper sha256 sum"
      When call machine clearlinux 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The output should match pattern '*'
      The error should include FAILED
    End
  End
End