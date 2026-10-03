# demo-aws-lambda-terraform-uv

A small, end-to-end example of a Python Lambda packaged with uv and deployed with Terraform. No Serverless Framework, and no CloudFormation.

I wrote a full walkthrough of this project on my blog: [Deploy a Python Lambda on AWS with uv and Terraform](https://dhrimov.dev/blog/deploy-python-lambda-uv-terraform). This README is the short version, enough to get the Lambda deployed. The article is where I explain the why behind each step.

Since then, I reworked the packaging script - reproducible builds, and automatic handling of the 250 MB Lambda size limit. That's covered in a follow-up post: [Packaging Python Lambdas with uv and package-python-function](https://dhrimov.dev/blog/python-lambda-packaging-uv-package-python-function).

The script is now a GitHub Action, [Package Python Lambda](https://github.com/marketplace/actions/package-python-lambda), and this repo uses it instead of keeping its own copy. That's covered in the third post: [TODO: post title](https://dhrimov.dev/blog/TODO).

## What it does

The Lambda parses its event into a pydantic model, reads a greeting from an environment variable, and logs a message like `Hi, World!`. It is intentionally small, but structured the way a real Lambda would be: multiple files, real dependencies, event parsing, and configuration through environment variables. I left out aws-lambda-powertools on purpose, to keep the moving parts to a minimum.

## Layout

```text
app/                       application code (handler, event model, settings)
terraform/                 infrastructure (Lambda, IAM role, log group)
.github/workflows/         CI: packages the Lambda with package-python-lambda-gha
pyproject.toml, uv.lock    dependencies
```

## Packaging in CI

[.github/workflows/package.yml](./.github/workflows/package.yml) packages the Lambda with [dhrimov/package-python-lambda-gha](https://github.com/dhrimov/package-python-lambda-gha) on every pull request and every push to `main`. It also uploads the zip as a workflow artifact, so you can download it from the run page. To get a zip without pushing anything, run the workflow by hand from the Actions tab.

The workflow only packages. It does not deploy.

## Prerequisites

- An AWS account, with credentials configured locally.
- Terraform CLI, version 1.10 or newer.
- uv installed. It manages Python 3.13 for you, so you do not need a separate Python.
- jq installed, if you package locally.
- A network connection on the first run. Packaging uses [package-python-function](https://github.com/BrandonLWhite/package-python-function), which the build script fetches with `uvx` rather than asking you to install it.

## Deploy

Get `terraform/app.zip` in one of two ways:

- Download the artifact from a workflow run, and put `app.zip` into `terraform/`.
- Package it locally with the action's `build.sh`:

```bash
git clone https://github.com/dhrimov/package-python-lambda-gha ../package-python-lambda-gha
../package-python-lambda-gha/build.sh --input . --output terraform --python 3.13 --platform aarch64-manylinux2014
```

Then run Terraform:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

If you would rather run every packaging step by hand and see what each one does, the first article walks through the commands in detail. To tear everything down, run `terraform apply -destroy` or `terraform destroy` from the `terraform/` directory.

> [!WARNING]
> The architecture and the runtime are pinned in two places, and they have to agree. If you move off arm64 or off Python 3.13, change both before you deploy:
>
> - `platform` and `python-version` in [.github/workflows/package.yml](./.github/workflows/package.yml) (or `--platform` and `--python` when you run `build.sh` locally)
> - `architectures` and `runtime` in [terraform/demo-lambda.tf](./terraform/demo-lambda.tf)
>
> If these drift apart, you will ship a Lambda whose code was built for one architecture or Python version but is configured to run on another, and it will fail at runtime.

The zip is named after the project's distribution name, so this repo produces `terraform/app.zip`.

### Edges to be aware of

- Be mindful that Terraform reads the zip on every plan and apply, so package before you plan. A stale `terraform/app.zip` will plan and apply without complaint.
- The build runs in `build/` at the repo root, and that directory is deleted before and after every build.
- The region, function name, greeting, and the like live in the Terraform files, and you change them there.
- It uses local Terraform state. That is fine for a demo like this one, but for anything shared or production you want a remote backend with state locking.
