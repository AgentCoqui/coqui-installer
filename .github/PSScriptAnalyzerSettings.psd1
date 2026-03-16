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
#
#   PSUseSingularNouns          — Same rationale as PSUseApprovedVerbs.
#                                 Check-Extensions is an internal helper that
#                                 checks multiple PHP extensions as a batch;
#                                 renaming it to Check-Extension would be
#                                 misleading about what the function does.
#
#   PSAvoidUsingEmptyCatchBlock — All empty catch blocks in these scripts are
#                                 intentional "best-effort" probes where the
#                                 failure is handled by testing the output
#                                 variable on the next line (e.g. querying
#                                 php -r, git stash, git rev-parse). The
#                                 alternative — using -ErrorAction
#                                 SilentlyContinue — does not suppress
#                                 terminating errors thrown by pwsh itself.
#
#   PSUseShouldProcessForStateChangingFunctions
#                               — ShouldProcess (-WhatIf / -Confirm) is
#                                 intended for module cmdlets, not for
#                                 internal functions inside a standalone
#                                 installer script that users run directly.

@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
