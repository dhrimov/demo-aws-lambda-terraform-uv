# demo-aws-lambda-terraform-uv

A small, end-to-end example of a Python Lambda packaged with uv and deployed with Terraform. No Serverless Framework, and no CloudFormation.

I wrote a full walkthrough of this project on my blog: [Deploy a Python Lambda on AWS with uv and Terraform](https://dhrimov.dev/blog/deploy-python-lambda-uv-terraform). This README is the short version, enough to get the Lambda deployed. The article is where I explain the why behind each step.

Since then, I reworked the packaging script - reproducible builds, and automatic handling of the 250 MB Lambda size limit. That's covered in a follow-up post: [Packaging Python Lambdas with uv and package-python-function](https://dhrimov.dev/blog/python-lambda-packaging-uv-package-python-function).

## What it does

The Lambda parses its event into a pydantic model, reads a greeting from an environment variable, and logs a message like `Hi, World!`. It is intentionally small, but structured the way a real Lambda would be: multiple files, real dependencies, event parsing, and configuration through environment variables. I left out aws-lambda-powertools on purpose, to keep the moving parts to a minimum.

## Layout

```text
app/                       application code (handler, event model, settings)
terraform/                 infrastructure (Lambda, IAM role, log group)
pyproject.toml, uv.lock    dependencies
```

## Prerequisites

- An AWS account, with credentials configured locally.
- Terraform CLI, version 1.10 or newer.
- uv installed. It manages Python 3.13 for you, so you do not need a separate Python.
- A network connection on the first run. Packaging uses [package-python-function](https://github.com/BrandonLWhite/package-python-function), which `build.sh` fetches with `uvx` rather than asking you to install it.

## Deploy

Package the Lambda, then run Terraform:

```bash
./build.sh --input . --output terraform --python 3.13 --platform aarch64-manylinux2014

cd terraform
terraform init
terraform plan
terraform apply
```

If you would rather run every packaging step by hand and see what each one does, the article walks through the commands in detail. To tear everything down, run `terraform apply -destroy` or `terraform destroy` from the `terraform/` directory.

## The build.sh script

It knows how to package a Python project and nothing else: no Terraform, and nothing specific to this repository. It exports locked dependencies with uv, builds the project as a wheel, installs both into a throwaway environment cross-compiled for the target platform, and zips the result with [package-python-function](https://github.com/BrandonLWhite/package-python-function).

Run `./build.sh --help` for the full list of arguments. `--input`, `--output`, `--python`, and `--platform` are required.

> [!WARNING]
> The architecture and the runtime are pinned in two places, and they have to agree. If you move off arm64 or off Python 3.13, change both before you deploy:
>
> - `--platform` and `--python` in the `build.sh` call
> - `architectures` and `runtime` in [terraform/demo-lambda.tf](./terraform/demo-lambda.tf)
>
> If these drift apart, you will ship a Lambda whose code was built for one architecture or Python version but is configured to run on another, and it will fail at runtime.

The zip is named after the project's distribution name, so this repo produces `terraform/app.zip`.

For the full walkthrough of how the script works - reproducible builds, the 250 MB size limit, and why the distribution name matters - see [Packaging Python Lambdas with uv and package-python-function](https://dhrimov.dev/blog/python-lambda-packaging-uv-package-python-function).

### Edges to be aware of

- Be mindful that Terraform reads the zip on every plan and apply, so package before you plan. A stale `terraform/app.zip` will plan and apply without complaint.
- The region, function name, greeting, and the like live in the Terraform files, and you change them there.
- It uses local Terraform state. That is fine for a demo like this one, but for anything shared or production you want a remote backend with state locking.