Describe "Compose"
  Describe "Alpine"
    Include ./spec/support/compose.sh

    It "installed compose"
      When call compose alpine
      The status should be success
      The output should include version
    End

    It "installed compose at precise version"
      When call compose alpine 1.25.3
      The status should be success
      The output should include 1.25.3
    End

    It "installed compose with proper sha256 sum"
      When call compose alpine 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c0050da98
      The status should be success
      The output should include 1.25.3
    End

    # On Alpine, pip-based installation fails because the implementation would
    # need to select and install the proper set of dependency packages.
    It "installed compose with improper sha256 sum"
      When call compose alpine 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The status should be failure
      The output should include failed
    End
  End

  Describe "Ubuntu"
    Include ./spec/support/compose.sh

    It "installed compose"
      When call compose ubuntu
      The status should be success
      The output should include version
    End

    It "installed compose at precise version"
      When call compose ubuntu 1.25.3
      The status should be success
      The output should include 1.25.3
    End

    It "installed compose with proper sha256 sum"
      When call compose ubuntu 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c0050da98
      The status should be success
      The output should include 1.25.3
    End

    It "installed compose with improper sha256 sum"
      When call compose ubuntu 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The status should be success
      The output should include 1.25.3
    End
  End

  Describe "ClearLinux"
    Include ./spec/support/compose.sh

    It "installed compose"
      When call compose ubuntu
      The status should be success
      The output should include version
    End

    It "installed compose at precise version"
      When call compose ubuntu 1.25.3
      The status should be success
      The output should include 1.25.3
    End

    It "installed compose with proper sha256 sum"
      When call compose ubuntu 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c0050da98
      The status should be success
      The output should include 1.25.3
    End

    # On ClearLinux, pip-based installation fails because the implementation would
    # need to select and install the proper set of dependency packages.
    It "installed compose with improper sha256 sum"
      When call compose ubuntu 1.25.3 b3835d30f66bd3b926511974138923713a253d634315479b9aa3166c00000000
      The status should be success
      The output should include 1.25.3
    End
  End

End