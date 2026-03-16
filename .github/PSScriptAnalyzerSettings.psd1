# PSScriptAnalyzer settings for coqui-installer scripts.
#
# Rules suppressed here are intentional design choices for installer scripts,
# not code quality issues:
#
#   PSAvoidUsingWriteHost       — Installer scripts must write directly to the
#                                 terminal host for interactive user output.
#                                 Write-Output / Write-Verbose are not suitable
#                                 here because they can be silently redirected.
#
#   PSUseBOMForUnicodeEncodedFile — The banner uses Unicode box-drawing
#                                 characters. A UTF-8 BOM is not required and
#                                 causes issues when scripts are downloaded and
#                                 piped via `irm | iex`.
#
#   PSUseApprovedVerbs          — These are private helper functions inside a
#                                 script file, not exported module cmdlets.
#                                 The approved-verb rule targets public API
#                                 surface; applying it to internal helpers
#                                 would force misleading names (e.g. renaming
#                                 Check-Php → Test-Php implies it only returns
#                                 a boolean, not that it installs PHP).

@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseApprovedVerbs'
    )
}
