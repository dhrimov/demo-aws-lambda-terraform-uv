# demo-aws-lambda-terraform-uv

A small, end-to-end example of a Python Lambda packaged with uv and deployed with Terraform. No Serverless Framework, and no CloudFormation.

I wrote a full walkthrough of this project on my blog: [Deploy a Python Lambda on AWS with uv and Terraform](https://dhrimov.dev/blog/deploy-python-lambda-uv-terraform). This README is the short version, enough to get the Lambda deployed. The article is where I explain the why behind each step.

## What it does

The Lambda parses its event into a pydantic model, reads a greeting from an environment variable, and logs a message like `Hi, World!`. It is intentionally small, but structured the way a real Lambda would be: multiple files, real dependencies, event parsing, and configuration through environment variables. I left out aws-lambda-powertools on purpose, to keep the moving parts to a minimum.

## Layout

```text
app/                       application code (handler, event model, settings)
terraform/                 infrastructure (Lambda, IAM role, log group)
deploy.sh                  package and deploy in one command
pyproject.toml, uv.lock    dependencies
```

## Prerequisites

- An AWS account, with credentials configured locally.
- Terraform CLI, version 1.10 or newer.
- uv installed. It manages Python 3.13 for you, so you do not need a separate Python.
- The zip utility, which ships with macOS and Linux.

## Deploy

The quick path is the script:

```bash
./deploy.sh plan     # package the Lambda and show the Terraform plan
./deploy.sh apply    # package the Lambda and apply (asks before changing anything)
```

If you would rather run every step by hand and see what each one does, the article walks through the packaging and Terraform commands in detail. To tear everything down, run `terraform apply -destroy` from the `terraform/` directory.

## The deploy.sh script

The script is not part of the article, so here is what it does and, more importantly, where its edges are.

What it does:

- Packages the app fresh for arm64: exports a locked `requirements.txt`, installs the dependencies into `build/`, zips them flat together with the `app/` code, and moves the archive to `terraform/lambda.zip`.
- Runs `terraform init`, then either `terraform plan` or `terraform apply`.
- Keeps `apply` interactive on purpose. Terraform shows the plan and waits for you to type `yes` before it changes anything.
- Cleans up the throwaway artifacts (`build/` and `requirements.txt`) when it exits. It leaves `terraform/lambda.zip` in place, because Terraform reads it on every run.

> [!NOTE]
> Be aware that AWS caps the Lambda deployment package at 250 MB unzipped, layers included. This demo is nowhere near the limit, but heavy dependencies like pandas or pyarrow will get you there faster than you might expect. The script keeps things simple and does not deal with the limit.
>
> A common way around it is to zip the requirements into their own archive first, and ship that archive inside the lambda package instead of the flat dependency files. Lambda only unzips the outer package, so the dependencies keep counting at their compressed size. At runtime, on the first cold start, the handler unzips the inner archive into `/tmp` and adds it to `sys.path` before any dependency import. The price is a slower cold start and a bit of bootstrap code, so reach for this only once you are actually close to the limit. Be mindful of `/tmp` as well - it defaults to 512 MB, so large dependencies may need more ephemeral storage configured on the function.

Drawbacks to be aware of:

- Both `plan` and `apply` rebuild the package from scratch. There is no caching and no reuse between runs. So running `plan` and then `apply` builds the zip twice. The archive `apply` ships is not guaranteed to be byte-for-byte identical to the one `plan` showed you, because the zip embeds file timestamps. The real safety gate is the interactive `yes` inside `apply`, not the earlier `plan`.
- The architecture is hardcoded in two places that must agree. If you want to move off arm64, change the platform in both files before you deploy:
  - the `--python-platform` value in [deploy.sh](./deploy.sh)
  - the `architectures` value in [terraform/demo-lambda.tf](./terraform/demo-lambda.tf)

  If these two drift apart, you will ship a Lambda whose code was built for one architecture but is configured to run on another, and it will fail at runtime.
- Nothing is configurable through flags. The region, function name, greeting, and the like live in the Terraform files and the script constants, and you change them there.
- It uses local Terraform state. That is fine for a demo like this one, but for anything shared or production you want a remote backend with state locking.