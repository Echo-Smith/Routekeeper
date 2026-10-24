# Routekeeper Terms and Disclaimer

Effective date: 2026-10-24

These terms apply to the Routekeeper application, source code, documentation and
related distributions. By using, copying or distributing Routekeeper, you agree
to these terms. If you do not agree, stop using the project and delete its files.

## 1. Nature of the software

Routekeeper is a native macOS utility for personal learning, technical exchange
and noncommercial research. It provides network inspection, egress verification
and optional Claude environment isolation. It is not an official Anthropic or
Claude product and is not affiliated with, authorized by or endorsed by
Anthropic, Google or any other third-party service provider.

Routekeeper is not antivirus software, a firewall, a virtual machine, an
anonymity service or an account risk-control tool. It does not guarantee that
traffic is protected, that an account remains available, or that a server will
not record, assess or restrict any activity.

## 2. License and permitted use

The source code is provided under the PolyForm Noncommercial License 1.0.0 in
the repository's `LICENSE` file. The license permits personal study, research,
experimentation and other noncommercial purposes, and prohibits commercial use.
Routekeeper is therefore source-available under a noncommercial license; it is
not open source under the OSI definition.

Commercial use, paid distribution, commercial integration and any other use
outside that license require separate prior written permission from the copyright
holder. Copyright, license and attribution notices must not be removed.

## 3. Prohibited use

You must not use Routekeeper to:

- violate applicable laws, regulations or regulatory requirements;
- circumvent lawful network or account restrictions or other security controls;
- infringe intellectual-property, privacy, account-security or other rights;
- attack, scan, disrupt or damage networks, devices, services or data;
- distribute malicious code, unlawful content or engage in fraud or harassment;
- pursue any commercial purpose, including paid distribution, bundling,
  commercial-service integration or operation in the project's name.

You must comply with the terms and policies of Claude, Anthropic, proxy clients,
browsers, DNS and network providers, and other third-party services. Local checks
or configuration do not change a third party's server-side records,
risk decisions, account status or regional assessment.

## 4. User responsibility

You are responsible for selecting, configuring and verifying the proxies,
networks, scripts, applications and third-party services you use, and for
ensuring that they are lawful, secure and appropriate for your environment.
Review possible effects and make backups before changing network, proxy, file,
sign-in or sandbox settings.

Routekeeper does not automatically copy a sandbox workspace back to the original
project and does not commit or push Git changes for you. Review every workspace,
patch and external handoff file before relying on or applying it.

## 5. Experimental sandbox

The experimental sandbox depends on macOS `sandbox-exec`, process identity checks,
an isolated HOME, workspace copies and a local relay. It may fail because of OS
changes, application updates, proxy configuration, permissions or other
environmental factors. It is a process and file boundary, not a virtual machine,
and does not virtualize all host network metadata or hardware information.

The sandbox does not guarantee account safety, device-fingerprint consistency,
server-side regional status or any risk-control outcome. Routekeeper asks you to
end the sandbox and confirm again before quitting. Save your work and verify that
sessions have ended.

## 6. Privacy and third-party requests

Routekeeper has no developer-operated account system, telemetry platform or
automatic report-upload service. Local data and network requests are described in
`PRIVACY.md`. Checks, proxies, Claude, Chrome, STUN, DNS and IP-information
services may still receive your public egress address, request metadata and other
information under their own policies.

## 7. No warranty

To the maximum extent permitted by law, Routekeeper is provided "as is" and
"as available", without express or implied warranties of accuracy, completeness,
availability, fitness for a particular purpose, non-infringement, security or
continued operation. Results may be incomplete, stale or environment-dependent,
and an unknown result must not be treated as a pass.

## 8. Limitation of liability

To the maximum extent permitted by law, the copyright holder, maintainers and
contributors are not liable for indirect, incidental, special, consequential or
punitive loss arising from use of or inability to use Routekeeper, including loss
of data, accounts, network access, devices, profits or business opportunities.
Rights that cannot legally be excluded or limited remain unaffected.

## 9. Changes and termination

These terms may change when features, data flows, licensing or legal requirements
change. Material updates will be identified through the in-app terms version,
repository commits or release notes. A violation of these terms or the `LICENSE`
may terminate your rights under the license; you must then stop using the project
and delete relevant copies.

## 10. Contact

Use GitHub Issues for general questions. Report security matters according to
`SECURITY.md`. Never post credentials, cookies, complete IP addresses, personal
paths or other sensitive information in a public issue.
