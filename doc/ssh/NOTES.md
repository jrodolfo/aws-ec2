EC2 SSH setup notes

1) Launch instance
- Create an EC2 instance (example: Amazon Linux 2023, `t3.small`).
- Ensure Security Group allows inbound `22/tcp` from your source IP.

2) Save key locally
- Place your key in `~/.ssh/`:
  - `~/.ssh/aws-training.pem`
- Set strict permissions:
  - `chmod 400 ~/.ssh/aws-training.pem`

3) Confirm correct Linux username
- Amazon Linux: `ec2-user`
- Ubuntu: `ubuntu`
- Debian: `admin` or `debian`

4) Optional SSH config entry
Use `~/.ssh/config`:

```sshconfig
Host my-ec2
  HostName 1.2.3.4
  User ec2-user
  IdentityFile ~/.ssh/aws-training.pem
  WarnWeakCrypto no  # optional
```

Where `1.2.3.4` is your EC2 public IP (or public DNS).

5) Connect
- Using host alias:
  - `ssh my-ec2`
- One-off command:
  - `ssh -i ~/.ssh/aws-training.pem ec2-user@<public-ip-or-dns>`

6) Troubleshooting
- If you see `Permission denied (publickey)`:
  - verify username matches AMI
  - verify key path is correct
  - run `chmod 400 ~/.ssh/<key>.pem`
  - verify Security Group allows inbound SSH (`22/tcp`)
- Debug authentication:
  - `ssh -vvv -i ~/.ssh/<key>.pem ec2-user@<public-ip-or-dns>`
