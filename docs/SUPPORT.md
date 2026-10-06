# Support the creator

Community support means starring DRACO, sharing a real Terminal capture, reporting
reproducible bugs, or contributing code/artwork with documented rights. It does
not require a payment account.

## Enable PayPal support as the creator

The repository is prepared for an external PayPal.Me link. No payment destination
is active yet, and no username/email has been guessed.

1. Create or copy your real link using [PayPal.Me](https://www.paypal.com/it/digital-wallet/send-receive-money/paypal-me).
2. From the DRACO checkout, run this command with your actual link:

```powershell
.\scripts\Set-CreatorSupport.ps1 -PayPalMeUrl 'https://paypal.me/YOUR_REAL_HANDLE'
```

3. Review `git diff`, then commit/push the README and `.github/FUNDING.yml` changes.

The script accepts only HTTPS PayPal.Me profile links, adds the README badge/link,
and configures GitHub's external Sponsor destination. It does not sign in, create
an account, submit a payment, run the installer or publish changes automatically.
GitHub displays the Sponsor button according to its funding settings.

DRACO does not process payments or store financial credentials. Available payment
methods are those shown by PayPal's own checkout for that account; a PayPal.Me
link does not add a separate Google Pay integration. Support remains optional and
unlocks no paid features. Follow the provider's account/usage terms.

