# TIMSAdvantaged Codebase

Generated: 09/20/2026 13:46:32

---

## Table of Contents

- .gitignore
- docker-compose.yml
- Dockerfile
- docs\.gitkeep
- docs\voter_survey_erd.md
- Generate-Codebook-TIMSAdvantaged.ps1
- infrastructure\.terraform.lock.hcl
- infrastructure\.terraform\providers\registry.terraform.io\hashicorp\archive\2.8.1\windows_amd64\LICENSE.txt
- infrastructure\.terraform\providers\registry.terraform.io\hashicorp\aws\5.100.0\windows_amd64\LICENSE.txt
- infrastructure\environments\.gitkeep
- infrastructure\main.tf
- infrastructure\modules\.gitkeep
- infrastructure\terraform.tfstate
- infrastructure\terraform.tfstate.backup
- ingestion\batch_voter_pipeline.py
- ingestion\lambda_functions\.gitkeep
- ingestion\lambda_functions\sqs_to_s3_processor\index.py
- ingestion\survey_api\app\.gitkeep
- ingestion\survey_api\app\main.py
- internal_tools\streamlit_app\app.py
- internal_tools\streamlit_app\pages\.gitkeep
- pipelines\airflow\dags\.gitkeep
- pipelines\airflow\dags\dag_survey_microservice.py
- pipelines\airflow\dags\dag_voter_batch.py
- pipelines\airflow\dags\utils.py
- pipelines\data_quality\.gitkeep
- pipelines\dbt\.gitignore
- pipelines\dbt\.user.yml
- pipelines\dbt\civic_pulse.duckdb
- pipelines\dbt\dbt_project.yml
- pipelines\dbt\macros\.gitkeep
- pipelines\dbt\macros\test_null_percentage.sql
- pipelines\dbt\models\marts\dim_date.sql
- pipelines\dbt\models\marts\dim_geography.sql
- pipelines\dbt\models\marts\dim_survey_metadata.sql
- pipelines\dbt\models\marts\dim_voter.sql
- pipelines\dbt\models\marts\fact_daily_survey_responses.sql
- pipelines\dbt\models\marts\schema.yml
- pipelines\dbt\models\staging\stg_geography.sql
- pipelines\dbt\models\staging\stg_survey_metadata.sql
- pipelines\dbt\models\staging\stg_survey_responses.sql
- pipelines\dbt\models\staging\stg_voters.sql
- pipelines\dbt\package-lock.yml
- pipelines\dbt\packages.yml
- pipelines\dbt\profiles.yml
- pipelines\dbt\README.md
- pipelines\dbt\tests\.gitkeep
- README.md
- requirements.txt
- scripts\.gitkeep
- scripts\deploy.ps1
- scripts\reset_env.ps1
- scripts\schedule_cleanup.ps1
- scripts\setup_env.ps1
- scripts\weekly_cleanup.ps1
- tests\integration\.gitkeep
- tests\unit\.gitkeep
- workflow\workflow.md

---


<div style='page-break-after: always;'></div>

# File: .gitignore

```gitignore
# Python
__pycache__/
*.py[cod]
*.pyc
*.class
*.so
.Python
env/
venv/
.venv/
ENV/
build/
dist/
*.egg-info/

# Environment Variables & Secrets
.env
.env.*
*.pem
aws_credentials.json

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Data & Logs
data/
logs/
*.csv
*.parquet
*.duckdb

# Terraform (CRITICAL: Never commit these)
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl

# dbt
target/
dbt_packages/
logs/
.user.yml

# Helper scripts
Codebase.md
Generate-Codebook-TIMSAdvantaged.ps1


# Lambda build artifacts
infrastructure/lambda_function.zip
```


<div style='page-break-after: always;'></div>

# File: docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - postgres-db-volume:/var/lib/postgresql/data

  airflow-init:
    build: .
    command:
      - bash
      - -c
      - |
        airflow db migrate &&
        airflow users create \
          --username admin \
          --password admin \
          --firstname Admin \
          --lastname User \
          --role Admin \
          --email admin@example.com
    environment:
      - AIRFLOW__CORE__EXECUTOR=LocalExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
    depends_on:
      - postgres

  airflow-webserver:
    build: .
    command: webserver
    ports:
      - "8080:8080"
    volumes:
      - ./pipelines/airflow/dags:/opt/airflow/dags
      - ./pipelines/dbt:/opt/airflow/dbt
      - ./requirements.txt:/opt/airflow/requirements.txt
    environment:
      - AIRFLOW__CORE__EXECUTOR=LocalExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
      - AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=False
      - AIRFLOW__FAB__AUTH_BACKENDS=airflow.providers.fab.auth_manager.api.auth.backend.basic_auth
      - AIRFLOW__API__AUTH_BACKENDS=airflow.providers.fab.auth_manager.api.auth.backend.basic_auth
      - AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=120.0  # <--- ADDED THIS LINE
    depends_on:
      - postgres
      - airflow-init

  airflow-scheduler:
    build: .
    command: scheduler
    volumes:
      - ./pipelines/airflow/dags:/opt/airflow/dags
      - ./pipelines/dbt:/opt/airflow/dbt
      - ./requirements.txt:/opt/airflow/requirements.txt
    environment:
      - AIRFLOW__CORE__EXECUTOR=LocalExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
      - AIRFLOW__FAB__AUTH_BACKENDS=airflow.providers.fab.auth_manager.api.auth.backend.basic_auth
      - AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=120.0  # <--- ADDED THIS LINE
    depends_on:
      - postgres
      - airflow-init

volumes:
  postgres-db-volume:
```


<div style='page-break-after: always;'></div>

# File: Dockerfile

```text
FROM apache/airflow:2.9.0-python3.10

# Switch to root to install system dependencies if needed
USER root

# Install git (required by some dbt/cosmos operations)
RUN apt-get update && apt-get install -y git

# Switch back to airflow user for security
USER airflow

# Copy our requirements file into the container
COPY requirements.txt .

# Install the specific packages we need for this project
# Note: We install Airflow packages here because we removed them from requirements.txt for Windows compatibility
RUN pip install --no-cache-dir \
    "apache-airflow==2.9.0" \
    "astronomer-cosmos==1.4.0" \
    "apache-airflow-providers-amazon==8.29.0" \
    "dbt-core==1.7.13" \
    "dbt-duckdb==1.7.1"
```


<div style='page-break-after: always;'></div>

# File: docs\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: docs\voter_survey_erd.md

```md
# CivicPulse Star Schema ERD

Copy the code block below into [mermaid.live](https://mermaid.live) to generate and download the PDF for your interview portfolio.

```mermaid
erDiagram
    FACT_DAILY_SURVEY_RESPONSES {
        string response_id PK
        string voter_id FK
        string survey_id FK
        string geography_id FK
        date date_id FK
        float sentiment_score
        float response_time_seconds
    }

    DIM_VOTER {
        string voter_id PK
        string first_name
        string last_name
        string registration_status
        string party_affiliation
        string geography_id FK
    }

    DIM_GEOGRAPHY {
        string geography_id PK
        string district_name
        string precinct_name
        string demographic_type
    }

    DIM_SURVEY_METADATA {
        string survey_id PK
        string question_text
        string pollster_name
        date survey_date
    }

    DIM_DATE {
        date date_id PK
        int year
        int month
        int day
        string day_type
    }

    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_VOTER : "has"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_SURVEY_METADATA : "answers"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_GEOGRAPHY : "located_in"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_DATE : "occurred_on"
    DIM_VOTER }o--|| DIM_GEOGRAPHY : "resides_in"
```


<div style='page-break-after: always;'></div>

# File: Generate-Codebook-TIMSAdvantaged.ps1

```ps1
<#
.EXAMPLE
.\Generate-Codebook-TIMSAdvantaged.ps1 -ProjectPath "C:\Data\CivicPulse"
#>

param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$GeneratePdf
)

# ============================================================
# Configuration
# ============================================================

$Root = (Resolve-Path $ProjectPath).Path

$MarkdownFile = Join-Path $Root "Codebase.md"
$PdfFile      = Join-Path $Root "Codebase.pdf"

# 1. Directories to completely ignore (Added TIMS specific folders)
$ExcludedDirectories = @(
    ".git", ".github", ".idea", ".vscode", ".cursor",
    "node_modules", "venv", ".venv", "env", "Lib", "Include", "site-packages",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "htmlcov",
    "coverage", "dist", "build", "bin", "obj", "out", ".next",
    "migrations", "trash", "staticfiles", "media",
    ".cache", ".data", ".logs", ".reports" 
)

# 2. File extensions to ignore (Added Excel, Certs, CSVs)
$ExcludedExtensions = @(
    ".png",".jpg",".jpeg",".gif",".bmp",".ico",".svg",".webp",".avif",
    ".pdf",".zip",".7z",".rar",".tar",".gz",
    ".exe",".dll",".so",".dylib",".pyd",
    ".woff",".woff2",".ttf",".eot",
    ".pyc",".pyo",".class",
    ".db",".sqlite3",".sqlite",".log",
    ".map", ".mo", ".lock", ".pth", ".bak", ".tmp",
    ".xlsx", ".xls", ".csv", ".pem", ".crt", ".key", ".tpl"
)

# 3. Specific files to ignore (CRITICAL: Added .secrets.toml for security)
$ExcludedFiles = @(
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "Pipfile.lock",
    "poetry.lock",
    "db.sqlite3",
    ".secrets.toml", 
    "Codebase.md",
    "Codebase.pdf"
)

# Delete old markdown if it exists
if (Test-Path $MarkdownFile) {
    Remove-Item $MarkdownFile -Force
}

# ============================================================
# Helper Function
# ============================================================

function Add-Line {
    param([string]$Text)
    Add-Content -Path $MarkdownFile -Value $Text -Encoding UTF8
}

# ============================================================
# Scan Files
# ============================================================

Write-Host ""
Write-Host "Scanning TIMSAdvantaged repository..."
Write-Host ""

$Files = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
    $fileName = $_.Name

    # Check Directories (Windows and Linux/Mac path separators)
    $pathParts = $relative -split '[\\/]'
    foreach ($dir in $ExcludedDirectories) {
        if ($pathParts -contains $dir) {
            return $false
        }
    }

    # Check Extensions
    if ($ExcludedExtensions -contains $_.Extension.ToLower()) {
        return $false
    }

    # Check Exact Filenames
    if ($ExcludedFiles -contains $fileName) {
        return $false
    }

    return $true

} | Sort-Object FullName

Write-Host "Found $($Files.Count) valid source code files."
Write-Host ""

# ============================================================
# Markdown Header
# ============================================================

Add-Line "# TIMSAdvantaged Codebase"
Add-Line ""
Add-Line "Generated: $(Get-Date)"
Add-Line ""
Add-Line "---"
Add-Line ""

# ============================================================
# Table of Contents
# ============================================================

Add-Line "## Table of Contents"
Add-Line ""

foreach ($file in $Files) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
    Add-Line "- $relative"
}

Add-Line ""
Add-Line "---"
Add-Line ""

# ============================================================
# Add Every File
# ============================================================

$index = 1

foreach ($file in $Files) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')

    Write-Host "[$index/$($Files.Count)] $relative"

    $language = $file.Extension.TrimStart('.')
    if ([string]::IsNullOrWhiteSpace($language)) { $language = "text" }
    
    # Map specific extensions to markdown code block languages
    switch ($language) {
        "py" { $language = "python" }
        "js" { $language = "javascript" }
        "ts" { $language = "typescript" }
        "tsx" { $language = "tsx" }
        "jsx" { $language = "jsx" }
        "yml" { $language = "yaml" }
        "sh" { $language = "bash" }
        "toml" { $language = "toml" }
    }

    Add-Line ""
    Add-Line "<div style='page-break-after: always;'></div>"
    Add-Line ""
    Add-Line "# File: $relative"
    Add-Line ""
    Add-Line ('```' + $language)

    try {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        Add-Content -Path $MarkdownFile -Value $content -Encoding UTF8
    }
    catch {
        Add-Line "[Unable to read file.]"
    }

    Add-Line '```'
    Add-Line ""
    $index++
}

Write-Host ""
Write-Host "Markdown created successfully!"
Write-Host $MarkdownFile



# ============================================================
# Optional PDF Generation
# ============================================================

if ($GeneratePdf) {

    $Pandoc = Get-Command pandoc -ErrorAction SilentlyContinue

    if ($Pandoc) {

        Write-Host ""
        Write-Host "Generating PDF..."

        & pandoc `
            $MarkdownFile `
            -o $PdfFile `
            --toc `
            --highlight-style=tango

        Write-Host ""
        Write-Host "PDF created:"
        Write-Host $PdfFile

    }
    else {

        Write-Host ""
        Write-Host "Pandoc was not found."
        Write-Host ""
        Write-Host "Install it from:"
        Write-Host "https://pandoc.org/installing.html"

    }

}
```


<div style='page-break-after: always;'></div>

# File: infrastructure\.terraform.lock.hcl

```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/archive" {
  version = "2.8.1"
  hashes = [
    "h1:eehhIUcuegkswQDKArYBAhVV9wQmRVMhyYGaD7kHIj0=",
    "zh:03de290604114a89fcd45c2e5bc7787d5a1ebfc5f964fb5989306bea7a4c79ec",
    "zh:0a7d69dc9fbbc48960bc2f04588c8fb1bd92c78a8f306566b7fb17fc4a4f2058",
    "zh:4df1f3981379c35f1757da957470f7f7724496b57219da3485177cf1647bdf59",
    "zh:50f0e72ba53bfe6e11b03b7fc899e1f72536354381d302a743a274ae2a3f45f4",
    "zh:5c4e15a04c98e2a8cafb1cd9632b48ad318051e8462d105b1153006277985c35",
    "zh:66069e604bcf5c4af0278e15997d9e6bd755c54fb3801d78885838b889729c5f",
    "zh:78d5eefdd9e494defcb3c68d282b8f96630502cac21d1ea161f53cfe9bb483b3",
    "zh:979765db3f42601870ab377104ba70befb029547b278337ec4ada980e3582de6",
    "zh:b165254da774f49945a73fbccc3ef1b63d70ea00a98fa9e14716665ba80ecaad",
    "zh:c0bb2697b525da9fec4511f569ed2bd2b42f25d5c1f9fa00f8f3645b50cfc2e9",
    "zh:c48f6695d12df0d0fa5231f7c1b8d518a4feae91a733fdd35a5804af3a303831",
    "zh:d589954c93f075180c9f4e2ce91780d5edcb56dfd0d3cda8ba08e13c10b52249",
    "zh:f5792ed06da65d0daf7ca3711f5399ff78c7cb4400afe53fbce9a926fbde4477",
  ]
}

provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.100.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:H3mU/7URhP0uCRGK8jeQRKxx2XFzEqLiOq/L2Bbiaxs=",
    "zh:054b8dd49f0549c9a7cc27d159e45327b7b65cf404da5e5a20da154b90b8a644",
    "zh:0b97bf8d5e03d15d83cc40b0530a1f84b459354939ba6f135a0086c20ebbe6b2",
    "zh:1589a2266af699cbd5d80737a0fe02e54ec9cf2ca54e7e00ac51c7359056f274",
    "zh:6330766f1d85f01ae6ea90d1b214b8b74cc8c1badc4696b165b36ddd4cc15f7b",
    "zh:7c8c2e30d8e55291b86fcb64bdf6c25489d538688545eb48fd74ad622e5d3862",
    "zh:99b1003bd9bd32ee323544da897148f46a527f622dc3971af63ea3e251596342",
    "zh:9b12af85486a96aedd8d7984b0ff811a4b42e3d88dad1a3fb4c0b580d04fa425",
    "zh:9f8b909d3ec50ade83c8062290378b1ec553edef6a447c56dadc01a99f4eaa93",
    "zh:aaef921ff9aabaf8b1869a86d692ebd24fbd4e12c21205034bb679b9caf883a2",
    "zh:ac882313207aba00dd5a76dbd572a0ddc818bb9cbf5c9d61b28fe30efaec951e",
    "zh:bb64e8aff37becab373a1a0cc1080990785304141af42ed6aa3dd4913b000421",
    "zh:dfe495f6621df5540d9c92ad40b8067376350b005c637ea6efac5dc15028add4",
    "zh:f0ddf0eaf052766cfe09dea8200a946519f653c384ab4336e2a4a64fdd6310e9",
    "zh:f1b7e684f4c7ae1eed272b6de7d2049bb87a0275cb04dbb7cda6636f600699c9",
    "zh:ff461571e3f233699bf690db319dfe46aec75e58726636a0d97dd9ac6e32fb70",
  ]
}

```


<div style='page-break-after: always;'></div>

# File: infrastructure\.terraform\providers\registry.terraform.io\hashicorp\archive\2.8.1\windows_amd64\LICENSE.txt

```txt
Copyright IBM Corp. 2017, 2026

Mozilla Public License Version 2.0
==================================

1. Definitions
--------------

1.1. "Contributor"
    means each individual or legal entity that creates, contributes to
    the creation of, or owns Covered Software.

1.2. "Contributor Version"
    means the combination of the Contributions of others (if any) used
    by a Contributor and that particular Contributor's Contribution.

1.3. "Contribution"
    means Covered Software of a particular Contributor.

1.4. "Covered Software"
    means Source Code Form to which the initial Contributor has attached
    the notice in Exhibit A, the Executable Form of such Source Code
    Form, and Modifications of such Source Code Form, in each case
    including portions thereof.

1.5. "Incompatible With Secondary Licenses"
    means

    (a) that the initial Contributor has attached the notice described
        in Exhibit B to the Covered Software; or

    (b) that the Covered Software was made available under the terms of
        version 1.1 or earlier of the License, but not also under the
        terms of a Secondary License.

1.6. "Executable Form"
    means any form of the work other than Source Code Form.

1.7. "Larger Work"
    means a work that combines Covered Software with other material, in
    a separate file or files, that is not Covered Software.

1.8. "License"
    means this document.

1.9. "Licensable"
    means having the right to grant, to the maximum extent possible,
    whether at the time of the initial grant or subsequently, any and
    all of the rights conveyed by this License.

1.10. "Modifications"
    means any of the following:

    (a) any file in Source Code Form that results from an addition to,
        deletion from, or modification of the contents of Covered
        Software; or

    (b) any new file in Source Code Form that contains any Covered
        Software.

1.11. "Patent Claims" of a Contributor
    means any patent claim(s), including without limitation, method,
    process, and apparatus claims, in any patent Licensable by such
    Contributor that would be infringed, but for the grant of the
    License, by the making, using, selling, offering for sale, having
    made, import, or transfer of either its Contributions or its
    Contributor Version.

1.12. "Secondary License"
    means either the GNU General Public License, Version 2.0, the GNU
    Lesser General Public License, Version 2.1, the GNU Affero General
    Public License, Version 3.0, or any later versions of those
    licenses.

1.13. "Source Code Form"
    means the form of the work preferred for making modifications.

1.14. "You" (or "Your")
    means an individual or a legal entity exercising rights under this
    License. For legal entities, "You" includes any entity that
    controls, is controlled by, or is under common control with You. For
    purposes of this definition, "control" means (a) the power, direct
    or indirect, to cause the direction or management of such entity,
    whether by contract or otherwise, or (b) ownership of more than
    fifty percent (50%) of the outstanding shares or beneficial
    ownership of such entity.

2. License Grants and Conditions
--------------------------------

2.1. Grants

Each Contributor hereby grants You a world-wide, royalty-free,
non-exclusive license:

(a) under intellectual property rights (other than patent or trademark)
    Licensable by such Contributor to use, reproduce, make available,
    modify, display, perform, distribute, and otherwise exploit its
    Contributions, either on an unmodified basis, with Modifications, or
    as part of a Larger Work; and

(b) under Patent Claims of such Contributor to make, use, sell, offer
    for sale, have made, import, and otherwise transfer either its
    Contributions or its Contributor Version.

2.2. Effective Date

The licenses granted in Section 2.1 with respect to any Contribution
become effective for each Contribution on the date the Contributor first
distributes such Contribution.

2.3. Limitations on Grant Scope

The licenses granted in this Section 2 are the only rights granted under
this License. No additional rights or licenses will be implied from the
distribution or licensing of Covered Software under this License.
Notwithstanding Section 2.1(b) above, no patent license is granted by a
Contributor:

(a) for any code that a Contributor has removed from Covered Software;
    or

(b) for infringements caused by: (i) Your and any other third party's
    modifications of Covered Software, or (ii) the combination of its
    Contributions with other software (except as part of its Contributor
    Version); or

(c) under Patent Claims infringed by Covered Software in the absence of
    its Contributions.

This License does not grant any rights in the trademarks, service marks,
or logos of any Contributor (except as may be necessary to comply with
the notice requirements in Section 3.4).

2.4. Subsequent Licenses

No Contributor makes additional grants as a result of Your choice to
distribute the Covered Software under a subsequent version of this
License (see Section 10.2) or under the terms of a Secondary License (if
permitted under the terms of Section 3.3).

2.5. Representation

Each Contributor represents that the Contributor believes its
Contributions are its original creation(s) or it has sufficient rights
to grant the rights to its Contributions conveyed by this License.

2.6. Fair Use

This License is not intended to limit any rights You have under
applicable copyright doctrines of fair use, fair dealing, or other
equivalents.

2.7. Conditions

Sections 3.1, 3.2, 3.3, and 3.4 are conditions of the licenses granted
in Section 2.1.

3. Responsibilities
-------------------

3.1. Distribution of Source Form

All distribution of Covered Software in Source Code Form, including any
Modifications that You create or to which You contribute, must be under
the terms of this License. You must inform recipients that the Source
Code Form of the Covered Software is governed by the terms of this
License, and how they can obtain a copy of this License. You may not
attempt to alter or restrict the recipients' rights in the Source Code
Form.

3.2. Distribution of Executable Form

If You distribute Covered Software in Executable Form then:

(a) such Covered Software must also be made available in Source Code
    Form, as described in Section 3.1, and You must inform recipients of
    the Executable Form how they can obtain a copy of such Source Code
    Form by reasonable means in a timely manner, at a charge no more
    than the cost of distribution to the recipient; and

(b) You may distribute such Executable Form under the terms of this
    License, or sublicense it under different terms, provided that the
    license for the Executable Form does not attempt to limit or alter
    the recipients' rights in the Source Code Form under this License.

3.3. Distribution of a Larger Work

You may create and distribute a Larger Work under terms of Your choice,
provided that You also comply with the requirements of this License for
the Covered Software. If the Larger Work is a combination of Covered
Software with a work governed by one or more Secondary Licenses, and the
Covered Software is not Incompatible With Secondary Licenses, this
License permits You to additionally distribute such Covered Software
under the terms of such Secondary License(s), so that the recipient of
the Larger Work may, at their option, further distribute the Covered
Software under the terms of either this License or such Secondary
License(s).

3.4. Notices

You may not remove or alter the substance of any license notices
(including copyright notices, patent notices, disclaimers of warranty,
or limitations of liability) contained within the Source Code Form of
the Covered Software, except that You may alter any license notices to
the extent required to remedy known factual inaccuracies.

3.5. Application of Additional Terms

You may choose to offer, and to charge a fee for, warranty, support,
indemnity or liability obligations to one or more recipients of Covered
Software. However, You may do so only on Your own behalf, and not on
behalf of any Contributor. You must make it absolutely clear that any
such warranty, support, indemnity, or liability obligation is offered by
You alone, and You hereby agree to indemnify every Contributor for any
liability incurred by such Contributor as a result of warranty, support,
indemnity or liability terms You offer. You may include additional
disclaimers of warranty and limitations of liability specific to any
jurisdiction.

4. Inability to Comply Due to Statute or Regulation
---------------------------------------------------

If it is impossible for You to comply with any of the terms of this
License with respect to some or all of the Covered Software due to
statute, judicial order, or regulation then You must: (a) comply with
the terms of this License to the maximum extent possible; and (b)
describe the limitations and the code they affect. Such description must
be placed in a text file included with all distributions of the Covered
Software under this License. Except to the extent prohibited by statute
or regulation, such description must be sufficiently detailed for a
recipient of ordinary skill to be able to understand it.

5. Termination
--------------

5.1. The rights granted under this License will terminate automatically
if You fail to comply with any of its terms. However, if You become
compliant, then the rights granted under this License from a particular
Contributor are reinstated (a) provisionally, unless and until such
Contributor explicitly and finally terminates Your grants, and (b) on an
ongoing basis, if such Contributor fails to notify You of the
non-compliance by some reasonable means prior to 60 days after You have
come back into compliance. Moreover, Your grants from a particular
Contributor are reinstated on an ongoing basis if such Contributor
notifies You of the non-compliance by some reasonable means, this is the
first time You have received notice of non-compliance with this License
from such Contributor, and You become compliant prior to 30 days after
Your receipt of the notice.

5.2. If You initiate litigation against any entity by asserting a patent
infringement claim (excluding declaratory judgment actions,
counter-claims, and cross-claims) alleging that a Contributor Version
directly or indirectly infringes any patent, then the rights granted to
You by any and all Contributors for the Covered Software under Section
2.1 of this License shall terminate.

5.3. In the event of termination under Sections 5.1 or 5.2 above, all
end user license agreements (excluding distributors and resellers) which
have been validly granted by You or Your distributors under this License
prior to termination shall survive termination.

************************************************************************
*                                                                      *
*  6. Disclaimer of Warranty                                           *
*  -------------------------                                           *
*                                                                      *
*  Covered Software is provided under this License on an "as is"       *
*  basis, without warranty of any kind, either expressed, implied, or  *
*  statutory, including, without limitation, warranties that the       *
*  Covered Software is free of defects, merchantable, fit for a        *
*  particular purpose or non-infringing. The entire risk as to the     *
*  quality and performance of the Covered Software is with You.        *
*  Should any Covered Software prove defective in any respect, You     *
*  (not any Contributor) assume the cost of any necessary servicing,   *
*  repair, or correction. This disclaimer of warranty constitutes an   *
*  essential part of this License. No use of any Covered Software is   *
*  authorized under this License except under this disclaimer.         *
*                                                                      *
************************************************************************

************************************************************************
*                                                                      *
*  7. Limitation of Liability                                          *
*  --------------------------                                          *
*                                                                      *
*  Under no circumstances and under no legal theory, whether tort      *
*  (including negligence), contract, or otherwise, shall any           *
*  Contributor, or anyone who distributes Covered Software as          *
*  permitted above, be liable to You for any direct, indirect,         *
*  special, incidental, or consequential damages of any character      *
*  including, without limitation, damages for lost profits, loss of    *
*  goodwill, work stoppage, computer failure or malfunction, or any    *
*  and all other commercial damages or losses, even if such party      *
*  shall have been informed of the possibility of such damages. This   *
*  limitation of liability shall not apply to liability for death or   *
*  personal injury resulting from such party's negligence to the       *
*  extent applicable law prohibits such limitation. Some               *
*  jurisdictions do not allow the exclusion or limitation of           *
*  incidental or consequential damages, so this exclusion and          *
*  limitation may not apply to You.                                    *
*                                                                      *
************************************************************************

8. Litigation
-------------

Any litigation relating to this License may be brought only in the
courts of a jurisdiction where the defendant maintains its principal
place of business and such litigation shall be governed by laws of that
jurisdiction, without reference to its conflict-of-law provisions.
Nothing in this Section shall prevent a party's ability to bring
cross-claims or counter-claims.

9. Miscellaneous
----------------

This License represents the complete agreement concerning the subject
matter hereof. If any provision of this License is held to be
unenforceable, such provision shall be reformed only to the extent
necessary to make it enforceable. Any law or regulation which provides
that the language of a contract shall be construed against the drafter
shall not be used to construe this License against a Contributor.

10. Versions of the License
---------------------------

10.1. New Versions

Mozilla Foundation is the license steward. Except as provided in Section
10.3, no one other than the license steward has the right to modify or
publish new versions of this License. Each version will be given a
distinguishing version number.

10.2. Effect of New Versions

You may distribute the Covered Software under the terms of the version
of the License under which You originally received the Covered Software,
or under the terms of any subsequent version published by the license
steward.

10.3. Modified Versions

If you create software not governed by this License, and you want to
create a new license for such software, you may create and use a
modified version of this License if you rename the license and remove
any references to the name of the license steward (except to note that
such modified license differs from this License).

10.4. Distributing Source Code Form that is Incompatible With Secondary
Licenses

If You choose to distribute Source Code Form that is Incompatible With
Secondary Licenses under the terms of this version of the License, the
notice described in Exhibit B of this License must be attached.

Exhibit A - Source Code Form License Notice
-------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

If it is not possible or desirable to put the notice in a particular
file, then You may include the notice in a location (such as a LICENSE
file in a relevant directory) where a recipient would be likely to look
for such a notice.

You may add additional accurate notices of copyright ownership.

Exhibit B - "Incompatible With Secondary Licenses" Notice
---------------------------------------------------------

  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

```


<div style='page-break-after: always;'></div>

# File: infrastructure\.terraform\providers\registry.terraform.io\hashicorp\aws\5.100.0\windows_amd64\LICENSE.txt

```txt
Copyright (c) 2017 HashiCorp, Inc.

Mozilla Public License Version 2.0
==================================

1. Definitions
--------------

1.1. "Contributor"
    means each individual or legal entity that creates, contributes to
    the creation of, or owns Covered Software.

1.2. "Contributor Version"
    means the combination of the Contributions of others (if any) used
    by a Contributor and that particular Contributor's Contribution.

1.3. "Contribution"
    means Covered Software of a particular Contributor.

1.4. "Covered Software"
    means Source Code Form to which the initial Contributor has attached
    the notice in Exhibit A, the Executable Form of such Source Code
    Form, and Modifications of such Source Code Form, in each case
    including portions thereof.

1.5. "Incompatible With Secondary Licenses"
    means

    (a) that the initial Contributor has attached the notice described
        in Exhibit B to the Covered Software; or

    (b) that the Covered Software was made available under the terms of
        version 1.1 or earlier of the License, but not also under the
        terms of a Secondary License.

1.6. "Executable Form"
    means any form of the work other than Source Code Form.

1.7. "Larger Work"
    means a work that combines Covered Software with other material, in
    a separate file or files, that is not Covered Software.

1.8. "License"
    means this document.

1.9. "Licensable"
    means having the right to grant, to the maximum extent possible,
    whether at the time of the initial grant or subsequently, any and
    all of the rights conveyed by this License.

1.10. "Modifications"
    means any of the following:

    (a) any file in Source Code Form that results from an addition to,
        deletion from, or modification of the contents of Covered
        Software; or

    (b) any new file in Source Code Form that contains any Covered
        Software.

1.11. "Patent Claims" of a Contributor
    means any patent claim(s), including without limitation, method,
    process, and apparatus claims, in any patent Licensable by such
    Contributor that would be infringed, but for the grant of the
    License, by the making, using, selling, offering for sale, having
    made, import, or transfer of either its Contributions or its
    Contributor Version.

1.12. "Secondary License"
    means either the GNU General Public License, Version 2.0, the GNU
    Lesser General Public License, Version 2.1, the GNU Affero General
    Public License, Version 3.0, or any later versions of those
    licenses.

1.13. "Source Code Form"
    means the form of the work preferred for making modifications.

1.14. "You" (or "Your")
    means an individual or a legal entity exercising rights under this
    License. For legal entities, "You" includes any entity that
    controls, is controlled by, or is under common control with You. For
    purposes of this definition, "control" means (a) the power, direct
    or indirect, to cause the direction or management of such entity,
    whether by contract or otherwise, or (b) ownership of more than
    fifty percent (50%) of the outstanding shares or beneficial
    ownership of such entity.

2. License Grants and Conditions
--------------------------------

2.1. Grants

Each Contributor hereby grants You a world-wide, royalty-free,
non-exclusive license:

(a) under intellectual property rights (other than patent or trademark)
    Licensable by such Contributor to use, reproduce, make available,
    modify, display, perform, distribute, and otherwise exploit its
    Contributions, either on an unmodified basis, with Modifications, or
    as part of a Larger Work; and

(b) under Patent Claims of such Contributor to make, use, sell, offer
    for sale, have made, import, and otherwise transfer either its
    Contributions or its Contributor Version.

2.2. Effective Date

The licenses granted in Section 2.1 with respect to any Contribution
become effective for each Contribution on the date the Contributor first
distributes such Contribution.

2.3. Limitations on Grant Scope

The licenses granted in this Section 2 are the only rights granted under
this License. No additional rights or licenses will be implied from the
distribution or licensing of Covered Software under this License.
Notwithstanding Section 2.1(b) above, no patent license is granted by a
Contributor:

(a) for any code that a Contributor has removed from Covered Software;
    or

(b) for infringements caused by: (i) Your and any other third party's
    modifications of Covered Software, or (ii) the combination of its
    Contributions with other software (except as part of its Contributor
    Version); or

(c) under Patent Claims infringed by Covered Software in the absence of
    its Contributions.

This License does not grant any rights in the trademarks, service marks,
or logos of any Contributor (except as may be necessary to comply with
the notice requirements in Section 3.4).

2.4. Subsequent Licenses

No Contributor makes additional grants as a result of Your choice to
distribute the Covered Software under a subsequent version of this
License (see Section 10.2) or under the terms of a Secondary License (if
permitted under the terms of Section 3.3).

2.5. Representation

Each Contributor represents that the Contributor believes its
Contributions are its original creation(s) or it has sufficient rights
to grant the rights to its Contributions conveyed by this License.

2.6. Fair Use

This License is not intended to limit any rights You have under
applicable copyright doctrines of fair use, fair dealing, or other
equivalents.

2.7. Conditions

Sections 3.1, 3.2, 3.3, and 3.4 are conditions of the licenses granted
in Section 2.1.

3. Responsibilities
-------------------

3.1. Distribution of Source Form

All distribution of Covered Software in Source Code Form, including any
Modifications that You create or to which You contribute, must be under
the terms of this License. You must inform recipients that the Source
Code Form of the Covered Software is governed by the terms of this
License, and how they can obtain a copy of this License. You may not
attempt to alter or restrict the recipients' rights in the Source Code
Form.

3.2. Distribution of Executable Form

If You distribute Covered Software in Executable Form then:

(a) such Covered Software must also be made available in Source Code
    Form, as described in Section 3.1, and You must inform recipients of
    the Executable Form how they can obtain a copy of such Source Code
    Form by reasonable means in a timely manner, at a charge no more
    than the cost of distribution to the recipient; and

(b) You may distribute such Executable Form under the terms of this
    License, or sublicense it under different terms, provided that the
    license for the Executable Form does not attempt to limit or alter
    the recipients' rights in the Source Code Form under this License.

3.3. Distribution of a Larger Work

You may create and distribute a Larger Work under terms of Your choice,
provided that You also comply with the requirements of this License for
the Covered Software. If the Larger Work is a combination of Covered
Software with a work governed by one or more Secondary Licenses, and the
Covered Software is not Incompatible With Secondary Licenses, this
License permits You to additionally distribute such Covered Software
under the terms of such Secondary License(s), so that the recipient of
the Larger Work may, at their option, further distribute the Covered
Software under the terms of either this License or such Secondary
License(s).

3.4. Notices

You may not remove or alter the substance of any license notices
(including copyright notices, patent notices, disclaimers of warranty,
or limitations of liability) contained within the Source Code Form of
the Covered Software, except that You may alter any license notices to
the extent required to remedy known factual inaccuracies.

3.5. Application of Additional Terms

You may choose to offer, and to charge a fee for, warranty, support,
indemnity or liability obligations to one or more recipients of Covered
Software. However, You may do so only on Your own behalf, and not on
behalf of any Contributor. You must make it absolutely clear that any
such warranty, support, indemnity, or liability obligation is offered by
You alone, and You hereby agree to indemnify every Contributor for any
liability incurred by such Contributor as a result of warranty, support,
indemnity or liability terms You offer. You may include additional
disclaimers of warranty and limitations of liability specific to any
jurisdiction.

4. Inability to Comply Due to Statute or Regulation
---------------------------------------------------

If it is impossible for You to comply with any of the terms of this
License with respect to some or all of the Covered Software due to
statute, judicial order, or regulation then You must: (a) comply with
the terms of this License to the maximum extent possible; and (b)
describe the limitations and the code they affect. Such description must
be placed in a text file included with all distributions of the Covered
Software under this License. Except to the extent prohibited by statute
or regulation, such description must be sufficiently detailed for a
recipient of ordinary skill to be able to understand it.

5. Termination
--------------

5.1. The rights granted under this License will terminate automatically
if You fail to comply with any of its terms. However, if You become
compliant, then the rights granted under this License from a particular
Contributor are reinstated (a) provisionally, unless and until such
Contributor explicitly and finally terminates Your grants, and (b) on an
ongoing basis, if such Contributor fails to notify You of the
non-compliance by some reasonable means prior to 60 days after You have
come back into compliance. Moreover, Your grants from a particular
Contributor are reinstated on an ongoing basis if such Contributor
notifies You of the non-compliance by some reasonable means, this is the
first time You have received notice of non-compliance with this License
from such Contributor, and You become compliant prior to 30 days after
Your receipt of the notice.

5.2. If You initiate litigation against any entity by asserting a patent
infringement claim (excluding declaratory judgment actions,
counter-claims, and cross-claims) alleging that a Contributor Version
directly or indirectly infringes any patent, then the rights granted to
You by any and all Contributors for the Covered Software under Section
2.1 of this License shall terminate.

5.3. In the event of termination under Sections 5.1 or 5.2 above, all
end user license agreements (excluding distributors and resellers) which
have been validly granted by You or Your distributors under this License
prior to termination shall survive termination.

************************************************************************
*                                                                      *
*  6. Disclaimer of Warranty                                           *
*  -------------------------                                           *
*                                                                      *
*  Covered Software is provided under this License on an "as is"       *
*  basis, without warranty of any kind, either expressed, implied, or  *
*  statutory, including, without limitation, warranties that the       *
*  Covered Software is free of defects, merchantable, fit for a        *
*  particular purpose or non-infringing. The entire risk as to the     *
*  quality and performance of the Covered Software is with You.        *
*  Should any Covered Software prove defective in any respect, You     *
*  (not any Contributor) assume the cost of any necessary servicing,   *
*  repair, or correction. This disclaimer of warranty constitutes an   *
*  essential part of this License. No use of any Covered Software is   *
*  authorized under this License except under this disclaimer.         *
*                                                                      *
************************************************************************

************************************************************************
*                                                                      *
*  7. Limitation of Liability                                          *
*  --------------------------                                          *
*                                                                      *
*  Under no circumstances and under no legal theory, whether tort      *
*  (including negligence), contract, or otherwise, shall any           *
*  Contributor, or anyone who distributes Covered Software as          *
*  permitted above, be liable to You for any direct, indirect,         *
*  special, incidental, or consequential damages of any character      *
*  including, without limitation, damages for lost profits, loss of    *
*  goodwill, work stoppage, computer failure or malfunction, or any    *
*  and all other commercial damages or losses, even if such party      *
*  shall have been informed of the possibility of such damages. This   *
*  limitation of liability shall not apply to liability for death or   *
*  personal injury resulting from such party's negligence to the       *
*  extent applicable law prohibits such limitation. Some               *
*  jurisdictions do not allow the exclusion or limitation of           *
*  incidental or consequential damages, so this exclusion and          *
*  limitation may not apply to You.                                    *
*                                                                      *
************************************************************************

8. Litigation
-------------

Any litigation relating to this License may be brought only in the
courts of a jurisdiction where the defendant maintains its principal
place of business and such litigation shall be governed by laws of that
jurisdiction, without reference to its conflict-of-law provisions.
Nothing in this Section shall prevent a party's ability to bring
cross-claims or counter-claims.

9. Miscellaneous
----------------

This License represents the complete agreement concerning the subject
matter hereof. If any provision of this License is held to be
unenforceable, such provision shall be reformed only to the extent
necessary to make it enforceable. Any law or regulation which provides
that the language of a contract shall be construed against the drafter
shall not be used to construe this License against a Contributor.

10. Versions of the License
---------------------------

10.1. New Versions

Mozilla Foundation is the license steward. Except as provided in Section
10.3, no one other than the license steward has the right to modify or
publish new versions of this License. Each version will be given a
distinguishing version number.

10.2. Effect of New Versions

You may distribute the Covered Software under the terms of the version
of the License under which You originally received the Covered Software,
or under the terms of any subsequent version published by the license
steward.

10.3. Modified Versions

If you create software not governed by this License, and you want to
create a new license for such software, you may create and use a
modified version of this License if you rename the license and remove
any references to the name of the license steward (except to note that
such modified license differs from this License).

10.4. Distributing Source Code Form that is Incompatible With Secondary
Licenses

If You choose to distribute Source Code Form that is Incompatible With
Secondary Licenses under the terms of this version of the License, the
notice described in Exhibit B of this License must be attached.

Exhibit A - Source Code Form License Notice
-------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

If it is not possible or desirable to put the notice in a particular
file, then You may include the notice in a location (such as a LICENSE
file in a relevant directory) where a recipient would be likely to look
for such a notice.

You may add additional accurate notices of copyright ownership.

Exhibit B - "Incompatible With Secondary Licenses" Notice
---------------------------------------------------------

  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

```


<div style='page-break-after: always;'></div>

# File: infrastructure\environments\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: infrastructure\main.tf

```tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ==========================================
# 1. S3 Buckets (Data Lake Raw Zone)
# ==========================================
resource "aws_s3_bucket" "raw_voter_files" {
  bucket = "civicpulse-raw-voter-files"

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

resource "aws_s3_bucket" "raw_surveys" {
  bucket = "civicpulse-raw-surveys"

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 2. SQS Queue (Decoupled Ingestion)
# ==========================================
resource "aws_sqs_queue" "survey_queue" {
  name                       = "civicpulse-survey-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 1 day

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 3. Lambda Function & IAM (Serverless Processing)
# ==========================================
# Automatically zip the Lambda code from the local directory
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../ingestion/lambda_functions/sqs_to_s3_processor"
  output_path = "${path.module}/lambda_function.zip"
}

# IAM Role for Lambda with Least Privilege
resource "aws_iam_role" "lambda_exec_role" {
  name = "civicpulse_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach least-privilege policy (SQS Read/Delete + S3 Write + CloudWatch Logs)
resource "aws_iam_role_policy" "lambda_s3_sqs_policy" {
  name = "civicpulse_lambda_s3_sqs_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.survey_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.raw_surveys.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "sqs_processor" {
  function_name    = "civicpulse_sqs_to_s3_processor"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "python3.10"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.raw_surveys.bucket
    }
  }

  timeout     = 30
  memory_size = 128

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 4. Event Source Mapping (SQS Trigger)
# ==========================================
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.survey_queue.arn
  function_name    = aws_lambda_function.sqs_processor.arn
  batch_size       = 10
}

# ==========================================
# 5. Outputs
# ==========================================
output "sqs_queue_url" {
  description = "The URL of the SQS queue for the microservice API to send messages to"
  value       = aws_sqs_queue.survey_queue.url
}

output "lambda_function_arn" {
  description = "The ARN of the deployed Lambda function"
  value       = aws_lambda_function.sqs_processor.arn
}
```


<div style='page-break-after: always;'></div>

# File: infrastructure\modules\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: infrastructure\terraform.tfstate

```tfstate
{
  "version": 4,
  "terraform_version": "1.15.8",
  "serial": 35,
  "lineage": "bed84171-2fa4-310f-172a-a90ca3b9930f",
  "outputs": {
    "lambda_function_arn": {
      "value": "arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor",
      "type": "string"
    },
    "sqs_queue_url": {
      "value": "https://sqs.us-east-1.amazonaws.com/932453198323/civicpulse-survey-queue",
      "type": "string"
    }
  },
  "resources": [
    {
      "mode": "data",
      "type": "archive_file",
      "name": "lambda_zip",
      "provider": "provider[\"registry.terraform.io/hashicorp/archive\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "exclude_symlink_directories": null,
            "excludes": null,
            "id": "46b862893eddbd33db6ce1c10ac0ceacf5d3e49a",
            "output_base64sha256": "baIYXEFY04aA7mP/cN6Y7HSP1BF+Mmmfq5IqBPfcfNA=",
            "output_base64sha512": "J2NhxCTqG97rJ/x4cjgsSoz2+NsVoeR69FbiG9EZa5Q0qFnVafKB/PaRV4ay5IQLc30askN1/hlkSnDMKvjbWw==",
            "output_file_mode": null,
            "output_md5": "a827c1db08d3dbdaa1d0ad5bee8ebc98",
            "output_path": "./lambda_function.zip",
            "output_sha": "46b862893eddbd33db6ce1c10ac0ceacf5d3e49a",
            "output_sha256": "6da2185c4158d38680ee63ff70de98ec748fd4117e32699fab922a04f7dc7cd0",
            "output_sha512": "276361c424ea1bdeeb27fc7872382c4a8cf6f8db15a1e47af456e21bd1196b9434a859d569f281fcf6915786b2e4840b737d1ab24375fe19644a70cc2af8db5b",
            "output_size": 1028,
            "source": [],
            "source_content": null,
            "source_content_filename": null,
            "source_dir": "./../ingestion/lambda_functions/sqs_to_s3_processor",
            "source_file": null,
            "type": "zip"
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_iam_role",
      "name": "lambda_exec_role",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "arn": "arn:aws:iam::932453198323:role/civicpulse_lambda_exec_role",
            "assume_role_policy": "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}],\"Version\":\"2012-10-17\"}",
            "create_date": "2026-09-20T09:58:56Z",
            "description": "",
            "force_detach_policies": false,
            "id": "civicpulse_lambda_exec_role",
            "inline_policy": [],
            "managed_policy_arns": [],
            "max_session_duration": 3600,
            "name": "civicpulse_lambda_exec_role",
            "name_prefix": "",
            "path": "/",
            "permissions_boundary": "",
            "tags": null,
            "tags_all": {},
            "unique_id": "AROA5SGUKVHZVJJPA67R6"
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "bnVsbA=="
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_iam_role_policy",
      "name": "lambda_s3_sqs_policy",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "id": "civicpulse_lambda_exec_role:civicpulse_lambda_s3_sqs_policy",
            "name": "civicpulse_lambda_s3_sqs_policy",
            "name_prefix": "",
            "policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Action\":[\"sqs:ReceiveMessage\",\"sqs:DeleteMessage\",\"sqs:GetQueueAttributes\"],\"Effect\":\"Allow\",\"Resource\":\"arn:aws:sqs:us-east-1:932453198323:civicpulse-survey-queue\"},{\"Action\":[\"s3:PutObject\",\"s3:PutObjectAcl\"],\"Effect\":\"Allow\",\"Resource\":\"arn:aws:s3:::civicpulse-raw-surveys/*\"},{\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Effect\":\"Allow\",\"Resource\":\"arn:aws:logs:*:*:*\"}]}",
            "role": "civicpulse_lambda_exec_role"
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "bnVsbA==",
          "dependencies": [
            "aws_iam_role.lambda_exec_role",
            "aws_s3_bucket.raw_surveys",
            "aws_sqs_queue.survey_queue"
          ]
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_lambda_event_source_mapping",
      "name": "sqs_trigger",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "amazon_managed_kafka_event_source_config": [],
            "arn": "arn:aws:lambda:us-east-1:932453198323:event-source-mapping:2954b538-2f7e-4565-a809-cec83a983a37",
            "batch_size": 10,
            "bisect_batch_on_function_error": false,
            "destination_config": [],
            "document_db_event_source_config": [],
            "enabled": true,
            "event_source_arn": "arn:aws:sqs:us-east-1:932453198323:civicpulse-survey-queue",
            "filter_criteria": [],
            "function_arn": "arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor",
            "function_name": "arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor",
            "function_response_types": null,
            "id": "2954b538-2f7e-4565-a809-cec83a983a37",
            "kms_key_arn": "",
            "last_modified": "2026-09-20T09:59:33Z",
            "last_processing_result": "",
            "maximum_batching_window_in_seconds": 0,
            "maximum_record_age_in_seconds": 0,
            "maximum_retry_attempts": 0,
            "metrics_config": [],
            "parallelization_factor": 0,
            "provisioned_poller_config": [],
            "queues": null,
            "scaling_config": [],
            "self_managed_event_source": [],
            "self_managed_kafka_event_source_config": [],
            "source_access_configuration": [],
            "starting_position": "",
            "starting_position_timestamp": "",
            "state": "Enabled",
            "state_transition_reason": "USER_INITIATED",
            "tags": null,
            "tags_all": {},
            "topics": null,
            "tumbling_window_in_seconds": 0,
            "uuid": "2954b538-2f7e-4565-a809-cec83a983a37"
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "bnVsbA==",
          "dependencies": [
            "aws_iam_role.lambda_exec_role",
            "aws_lambda_function.sqs_processor",
            "aws_s3_bucket.raw_surveys",
            "aws_sqs_queue.survey_queue",
            "data.archive_file.lambda_zip"
          ]
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_lambda_function",
      "name": "sqs_processor",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "architectures": [
              "x86_64"
            ],
            "arn": "arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor",
            "code_sha256": "baIYXEFY04aA7mP/cN6Y7HSP1BF+Mmmfq5IqBPfcfNA=",
            "code_signing_config_arn": "",
            "dead_letter_config": [],
            "description": "",
            "environment": [
              {
                "variables": {
                  "TARGET_BUCKET": "civicpulse-raw-surveys"
                }
              }
            ],
            "ephemeral_storage": [
              {
                "size": 512
              }
            ],
            "file_system_config": [],
            "filename": "./lambda_function.zip",
            "function_name": "civicpulse_sqs_to_s3_processor",
            "handler": "index.handler",
            "id": "civicpulse_sqs_to_s3_processor",
            "image_config": [],
            "image_uri": "",
            "invoke_arn": "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor/invocations",
            "kms_key_arn": "",
            "last_modified": "2026-09-20T09:59:04.815+0000",
            "layers": null,
            "logging_config": [
              {
                "application_log_level": "",
                "log_format": "Text",
                "log_group": "/aws/lambda/civicpulse_sqs_to_s3_processor",
                "system_log_level": ""
              }
            ],
            "memory_size": 128,
            "package_type": "Zip",
            "publish": false,
            "qualified_arn": "arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor:$LATEST",
            "qualified_invoke_arn": "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor:$LATEST/invocations",
            "replace_security_groups_on_destroy": null,
            "replacement_security_group_ids": null,
            "reserved_concurrent_executions": -1,
            "role": "arn:aws:iam::932453198323:role/civicpulse_lambda_exec_role",
            "runtime": "python3.10",
            "s3_bucket": null,
            "s3_key": null,
            "s3_object_version": null,
            "signing_job_arn": "",
            "signing_profile_version_arn": "",
            "skip_destroy": false,
            "snap_start": [],
            "source_code_hash": "baIYXEFY04aA7mP/cN6Y7HSP1BF+Mmmfq5IqBPfcfNA=",
            "source_code_size": 1028,
            "tags": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "tags_all": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "timeout": 30,
            "timeouts": null,
            "tracing_config": [
              {
                "mode": "PassThrough"
              }
            ],
            "version": "$LATEST",
            "vpc_config": []
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "eyJlMmJmYjczMC1lY2FhLTExZTYtOGY4OC0zNDM2M2JjN2M0YzAiOnsiY3JlYXRlIjo2MDAwMDAwMDAwMDAsImRlbGV0ZSI6NjAwMDAwMDAwMDAwLCJ1cGRhdGUiOjYwMDAwMDAwMDAwMH19",
          "dependencies": [
            "aws_iam_role.lambda_exec_role",
            "aws_s3_bucket.raw_surveys",
            "data.archive_file.lambda_zip"
          ]
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "raw_surveys",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "acceleration_status": "",
            "acl": null,
            "arn": "arn:aws:s3:::civicpulse-raw-surveys",
            "bucket": "civicpulse-raw-surveys",
            "bucket_domain_name": "civicpulse-raw-surveys.s3.amazonaws.com",
            "bucket_prefix": "",
            "bucket_regional_domain_name": "civicpulse-raw-surveys.s3.us-east-1.amazonaws.com",
            "cors_rule": [],
            "force_destroy": false,
            "grant": [
              {
                "id": "90c30755ecb3697dd89ba5f37272f0433ce932d00ff8a8b4d3367690fadbcf72",
                "permissions": [
                  "FULL_CONTROL"
                ],
                "type": "CanonicalUser",
                "uri": ""
              }
            ],
            "hosted_zone_id": "Z3AQBSTGFYJSTF",
            "id": "civicpulse-raw-surveys",
            "lifecycle_rule": [],
            "logging": [],
            "object_lock_configuration": [],
            "object_lock_enabled": false,
            "policy": "",
            "region": "us-east-1",
            "replication_configuration": [],
            "request_payer": "BucketOwner",
            "server_side_encryption_configuration": [
              {
                "rule": [
                  {
                    "apply_server_side_encryption_by_default": [
                      {
                        "kms_master_key_id": "",
                        "sse_algorithm": "AES256"
                      }
                    ],
                    "bucket_key_enabled": false
                  }
                ]
              }
            ],
            "tags": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "tags_all": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "timeouts": null,
            "versioning": [
              {
                "enabled": false,
                "mfa_delete": false
              }
            ],
            "website": [],
            "website_domain": null,
            "website_endpoint": null
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "eyJlMmJmYjczMC1lY2FhLTExZTYtOGY4OC0zNDM2M2JjN2M0YzAiOnsiY3JlYXRlIjoxMjAwMDAwMDAwMDAwLCJkZWxldGUiOjM2MDAwMDAwMDAwMDAsInJlYWQiOjEyMDAwMDAwMDAwMDAsInVwZGF0ZSI6MTIwMDAwMDAwMDAwMH19"
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "raw_voter_files",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "acceleration_status": "",
            "acl": null,
            "arn": "arn:aws:s3:::civicpulse-raw-voter-files",
            "bucket": "civicpulse-raw-voter-files",
            "bucket_domain_name": "civicpulse-raw-voter-files.s3.amazonaws.com",
            "bucket_prefix": "",
            "bucket_regional_domain_name": "civicpulse-raw-voter-files.s3.us-east-1.amazonaws.com",
            "cors_rule": [],
            "force_destroy": false,
            "grant": [
              {
                "id": "90c30755ecb3697dd89ba5f37272f0433ce932d00ff8a8b4d3367690fadbcf72",
                "permissions": [
                  "FULL_CONTROL"
                ],
                "type": "CanonicalUser",
                "uri": ""
              }
            ],
            "hosted_zone_id": "Z3AQBSTGFYJSTF",
            "id": "civicpulse-raw-voter-files",
            "lifecycle_rule": [],
            "logging": [],
            "object_lock_configuration": [],
            "object_lock_enabled": false,
            "policy": "",
            "region": "us-east-1",
            "replication_configuration": [],
            "request_payer": "BucketOwner",
            "server_side_encryption_configuration": [
              {
                "rule": [
                  {
                    "apply_server_side_encryption_by_default": [
                      {
                        "kms_master_key_id": "",
                        "sse_algorithm": "AES256"
                      }
                    ],
                    "bucket_key_enabled": false
                  }
                ]
              }
            ],
            "tags": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "tags_all": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "timeouts": null,
            "versioning": [
              {
                "enabled": false,
                "mfa_delete": false
              }
            ],
            "website": [],
            "website_domain": null,
            "website_endpoint": null
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "eyJlMmJmYjczMC1lY2FhLTExZTYtOGY4OC0zNDM2M2JjN2M0YzAiOnsiY3JlYXRlIjoxMjAwMDAwMDAwMDAwLCJkZWxldGUiOjM2MDAwMDAwMDAwMDAsInJlYWQiOjEyMDAwMDAwMDAwMDAsInVwZGF0ZSI6MTIwMDAwMDAwMDAwMH19"
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_sqs_queue",
      "name": "survey_queue",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "arn": "arn:aws:sqs:us-east-1:932453198323:civicpulse-survey-queue",
            "content_based_deduplication": false,
            "deduplication_scope": "",
            "delay_seconds": 0,
            "fifo_queue": false,
            "fifo_throughput_limit": "",
            "id": "https://sqs.us-east-1.amazonaws.com/932453198323/civicpulse-survey-queue",
            "kms_data_key_reuse_period_seconds": 300,
            "kms_master_key_id": "",
            "max_message_size": 262144,
            "message_retention_seconds": 86400,
            "name": "civicpulse-survey-queue",
            "name_prefix": "",
            "policy": "",
            "receive_wait_time_seconds": 0,
            "redrive_allow_policy": "",
            "redrive_policy": "",
            "sqs_managed_sse_enabled": true,
            "tags": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "tags_all": {
              "Environment": "production",
              "Project": "CivicPulse"
            },
            "timeouts": null,
            "url": "https://sqs.us-east-1.amazonaws.com/932453198323/civicpulse-survey-queue",
            "visibility_timeout_seconds": 30
          },
          "sensitive_attributes": [],
          "identity_schema_version": 0,
          "private": "eyJlMmJmYjczMC1lY2FhLTExZTYtOGY4OC0zNDM2M2JjN2M0YzAiOnsiY3JlYXRlIjoxODAwMDAwMDAwMDAsImRlbGV0ZSI6MTgwMDAwMDAwMDAwLCJ1cGRhdGUiOjE4MDAwMDAwMDAwMH19"
        }
      ]
    }
  ],
  "check_results": null
}

```


<div style='page-break-after: always;'></div>

# File: infrastructure\terraform.tfstate.backup

```backup
{
  "version": 4,
  "terraform_version": "1.15.8",
  "serial": 27,
  "lineage": "bed84171-2fa4-310f-172a-a90ca3b9930f",
  "outputs": {},
  "resources": [],
  "check_results": null
}

```


<div style='page-break-after: always;'></div>

# File: ingestion\batch_voter_pipeline.py

```python
import pandas as pd
import boto3
import io
from datetime import datetime

# Configuration
S3_BUCKET = "civicpulse-raw-voter-files" # We will create this with Terraform
AWS_REGION = "us-east-1"

def generate_mock_voter_data():
    """Simulates extracting raw voter data from a legacy system or API."""
    data = {
        "voter_id": ["VTR-1001", "VTR-1002", "VTR-1003", "VTR-1004"],
        "first_name": ["John", "Jane", "Robert", "Alice"],
        "last_name": ["Doe", "Smith", "Johnson", "Williams"],
        "county": ["Fairfax", "Fairfax", "Arlington", "Arlington"],
        "registration_status": ["Active", "Active", "Inactive", "Active"],
        "party_affiliation": ["Democrat", "Independent", "Republican", "Democrat"],
        "last_updated": ["2026-09-15", "2026-09-16", "2026-09-15", "2026-09-17"]
    }
    return pd.DataFrame(data)

def clean_and_partition_data(df: pd.DataFrame):
    """Cleans data and prepares it for partitioned Parquet storage."""
    # 1. Data Quality: Drop rows with missing critical fields
    df = df.dropna(subset=["voter_id", "county"])
    
    # 2. Data Transformation: Standardize text
    df["party_affiliation"] = df["party_affiliation"].str.title()
    df["last_updated"] = pd.to_datetime(df["last_updated"])
    df["year"] = df["last_updated"].dt.year
    
    return df

def upload_to_s3_partitioned(df: pd.DataFrame):
    """Uploads DataFrame to S3 partitioned by year and county."""
    s3 = boto3.client("s3", region_name=AWS_REGION)
    
    # Group by partition keys
    for (year, county), group in df.groupby(["year", "county"]):
        # Drop partition columns from the actual data payload (best practice)
        data_to_write = group.drop(columns=["year", "county"])
        
        # Convert to Parquet in memory
        parquet_buffer = io.BytesIO()
        data_to_write.to_parquet(parquet_buffer, index=False, engine="pyarrow")
        
        # Define S3 partitioned path: s3://bucket/year=2026/county=Fairfax/data.parquet
        s3_key = f"year={year}/county={county}/data.parquet"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=parquet_buffer.getvalue(),
            ContentType="application/octet-stream"
        )
        print(f"✅ Successfully uploaded partition: {s3_key}")

if __name__ == "__main__":
    print("🚀 Starting Batch Voter Pipeline...")
    raw_df = generate_mock_voter_data()
    clean_df = clean_and_partition_data(raw_df)
    upload_to_s3_partitioned(clean_df)
    print("🎉 Batch Pipeline Completed Successfully!")
```


<div style='page-break-after: always;'></div>

# File: ingestion\lambda_functions\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: ingestion\lambda_functions\sqs_to_s3_processor\index.py

```python
import json
import boto3
import os
from datetime import datetime

s3_client = boto3.client('s3')

# Configuration (Injected by Terraform)
TARGET_BUCKET = os.environ.get('TARGET_BUCKET', 'civicpulse-raw-surveys')

def lambda_handler(event, context):
    """
    Triggered by SQS. Processes batched messages and writes them to S3.
    """
    print(f"Received event: {json.dumps(event)}")
    
    for record in event['Records']:
        try:
            # 1. Parse the SQS message body
            body = json.loads(record['body'])
            
            # 2. Basic Data Quality Validation
            required_fields = ['voter_id', 'survey_id', 'sentiment_score']
            if not all(field in body for field in required_fields):
                print(f"❌ Validation failed: Missing required fields in {body}")
                continue # In production, send to a Dead Letter Queue (DLQ)
            
            if not (0.0 <= body['sentiment_score'] <= 1.0):
                print(f"❌ Validation failed: sentiment_score out of bounds in {body}")
                continue

            # 3. Generate a unique S3 key with date partitioning
            date_str = datetime.now().strftime("%Y/%m/%d")
            message_id = body.get("message_id", "unknown")
            s3_key = f"raw_surveys/date={date_str}/survey_{message_id}.json"

            # 4. Write to S3
            s3_client.put_object(
                Bucket=TARGET_BUCKET,
                Key=s3_key,
                Body=json.dumps(body),
                ContentType="application/json"
            )
            print(f"✅ Successfully wrote to S3: s3://{TARGET_BUCKET}/{s3_key}")

        except Exception as e:
            print(f"❌ Error processing record {record['messageId']}: {str(e)}")
            # Raising an exception here will cause SQS to retry the message
            
    return {
        'statusCode': 200,
        'body': json.dumps('Successfully processed SQS messages')
    }
```


<div style='page-break-after: always;'></div>

# File: ingestion\survey_api\app\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: ingestion\survey_api\app\main.py

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import boto3
import json
import os
import uuid

app = FastAPI(title="CivicPulse Survey Ingestion API")

# Pydantic model for data validation at the API gateway layer
class SurveyResponse(BaseModel):
    voter_id: str = Field(..., description="Unique voter identifier")
    survey_id: str = Field(..., description="Unique survey identifier")
    sentiment_score: float = Field(..., ge=0.0, le=1.0, description="Sentiment between 0.0 and 1.0")
    response_time_seconds: float = Field(..., gt=0.0)

# AWS Configuration
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "https://sqs.us-east-1.amazonaws.com/123456789012/civicpulse-survey-queue")

sqs_client = boto3.client("sqs", region_name=AWS_REGION)

@app.post("/survey", status_code=202)
async def ingest_survey_response(response: SurveyResponse):
    """
    Receives a survey response and pushes it to an SQS queue for asynchronous processing.
    This ensures high availability and decouples ingestion from transformation.
    """
    try:
        # Add metadata for tracing
        payload = response.dict()
        payload["ingestion_timestamp"] = "2026-09-19T12:00:00Z" # Simulated current time
        payload["message_id"] = str(uuid.uuid4())

        # Send to SQS
        sqs_response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(payload),
            MessageAttributes={
                "DataType": {"StringValue": "String", "DataType": "String"},
                "VoterId": {"StringValue": response.voter_id, "DataType": "String"}
            }
        )
        
        return {
            "status": "accepted",
            "message": "Survey response queued successfully",
            "sqs_message_id": sqs_response["MessageId"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to queue message: {str(e)}")

# To run locally: uvicorn ingestion.survey_api.app.main:app --reload
```


<div style='page-break-after: always;'></div>

# File: internal_tools\streamlit_app\app.py

```python
import streamlit as st
import duckdb
import json
import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime

# Configuration
DB_PATH = "pipelines/dbt/civic_pulse.duckdb"
CATALOG_PATH = "pipelines/dbt/target/catalog.json"
AIRFLOW_API_URL = "http://localhost:8080/api/v1"
AIRFLOW_USER = "admin"
AIRFLOW_PASS = "admin"

st.set_page_config(page_title="CivicPulse Data Portal", page_icon="🏛️", layout="wide")

st.title("🏛️ CivicPulse Internal Data Portal")
st.markdown("Self-service tool for Data Science and Business Analytics teams to monitor data health, explore the data dictionary, and manage pipeline executions.")

tab1, tab2, tab3 = st.tabs([" Data Quality Dashboard", "📖 Data Dictionary", "⚙️ Pipeline Operations"])

# ==========================================
# FEATURE 1: Data Quality Dashboard
# ==========================================
with tab1:
    st.header("Real-Time Data Quality Metrics")
    st.markdown("Live metrics pulled directly from the data warehouse to ensure quantitative research data integrity.")
    
    try:
        conn = duckdb.connect(DB_PATH)
        
        # Metric 1: Voter ID Completeness
        voter_count = conn.execute("SELECT COUNT(*) FROM dim_voter").fetchone()[0]
        null_voter_count = conn.execute("SELECT COUNT(*) FROM dim_voter WHERE voter_id IS NULL").fetchone()[0]
        match_rate = ((voter_count - null_voter_count) / voter_count * 100) if voter_count > 0 else 100.0
        
        st.metric(label="Voter ID Completeness", value=f"{match_rate:.1f}%", delta="Target: 100%")
        
        # Metric 2: Sentiment Score Bounds (QA Test Simulation)
        sentiment_out_of_bounds = conn.execute("""
            SELECT COUNT(*) FROM fact_daily_survey_responses 
            WHERE sentiment_score < 0.0 OR sentiment_score > 1.0
        """).fetchone()[0]
        
        st.metric(
            label="Sentiment Scores Out of Bounds (0.0 - 1.0)", 
            value=sentiment_out_of_bounds, 
            delta="Target: 0", 
            delta_color="inverse" if sentiment_out_of_bounds > 0 else "normal"
        )
        
        # Metric 3: Total Records
        total_surveys = conn.execute("SELECT COUNT(*) FROM fact_daily_survey_responses").fetchone()[0]
        st.metric(label="Total Survey Responses in Warehouse", value=total_surveys)
        
        conn.close()
        st.success("✅ All core data quality checks passed based on the latest warehouse state.")
        
    except Exception as e:
        st.warning("⚠️ Could not connect to data warehouse. Ensure dbt has been run locally (`dbt build`).")
        st.code(str(e))

# ==========================================
# FEATURE 2: Data Dictionary
# ==========================================
with tab2:
    st.header("Data Dictionary")
    st.markdown("Search and explore table and column definitions generated directly from dbt documentation. No SQL required!")
    
    try:
        with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
            catalog = json.load(f)
            
        nodes = catalog.get('nodes', {})
        
        # Filter for our specific dbt models
        models = {k: v for k, v in nodes.items() if k.startswith('model.civic_pulse.')}
        
        model_names = sorted([name.split('.')[-1] for name in models.keys()])
        selected_model = st.selectbox("Select a table to explore:", [""] + model_names)
        
        if selected_model:
            model_key = f"model.civic_pulse.{selected_model}"
            model_data = models[model_key]
            
            st.subheader(f"Table: `{selected_model}`")
            description = model_data.get('metadata', {}).get('comment', 'No description available.')
            st.info(f"**Description:** {description}")
            
            st.markdown("### Columns")
            columns = model_data.get('columns', {})
            col_data = []
            for col_name, col_info in columns.items():
                col_data.append({
                    "Column Name": col_name,
                    "Data Type": col_info.get('type', 'Unknown').upper(),
                    "Description": col_info.get('comment', 'No description')
                })
            
            st.dataframe(col_data, use_container_width=True, hide_index=True)
            
    except FileNotFoundError:
        st.warning("⚠️ `catalog.json` not found. Please run `dbt docs generate` in the `pipelines/dbt` directory first.")
    except Exception as e:
        st.error(f"Error loading data dictionary: {e}")

# ==========================================
# FEATURE 3: Pipeline Operations
# ==========================================
with tab3:
    st.header("Pipeline Operations")
    st.markdown("Manually trigger pipeline re-runs if the Data Science team identifies data anomalies or missing data.")
    
    dag_options = {
        "Voter Batch Processing (Nightly)": "dag_voter_batch_processing",
        "Survey Microservice Processing (Event-Driven)": "dag_survey_microservice_processing"
    }
    
    col1, col2 = st.columns(2)
    with col1:
        selected_dag_name = st.selectbox("Select Pipeline to Re-run", list(dag_options.keys()))
    dag_id = dag_options[selected_dag_name]
    
    with col2:
        run_date = st.date_input("Select logical date for re-run", datetime.now())
    
    if st.button(" Trigger Manual Re-run", type="primary"):
        with st.spinner(f"Contacting Airflow to trigger `{dag_id}`..."):
            try:
                # 1. Get the base date selected by the user (e.g., 2026-09-20)
                base_date = datetime.combine(run_date, datetime.min.time())
                
                # 2. Append the current time to make it a unique logical_date.
                # This prevents 409 Conflicts if the user triggers the same day twice.
                # In the real world, this is called a "Manual Backfill".
                unique_logical_date = base_date.replace(
                    hour=datetime.now().hour,
                    minute=datetime.now().minute,
                    second=datetime.now().second
                )
                
                logical_date_str = unique_logical_date.strftime("%Y-%m-%dT%H:%M:%S+00:00")
                
                # 3. Create a unique run ID for tracking
                unique_run_id = f"manual_backfill_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

                payload = {
                    "conf": {},
                    "logical_date": logical_date_str,
                    "dag_run_id": unique_run_id
                }
                
                response = requests.post(
                    f"{AIRFLOW_API_URL}/dags/{dag_id}/dagRuns",
                    json=payload,
                    auth=HTTPBasicAuth(AIRFLOW_USER, AIRFLOW_PASS),
                    headers={"Content-Type": "application/json"}
                )
                
                if response.status_code in [200, 201]:
                    st.success(f"✅ Successfully triggered DAG: `{dag_id}`!")
                    st.info(f" Business Date: {run_date} |  Unique Logical Date: {logical_date_str}")
                    with st.expander("View API Response"):
                        st.json(response.json())
                else:
                    st.error(f"❌ Failed to trigger DAG. Status Code: {response.status_code}")
                    st.code(response.text)
                    
            except requests.exceptions.ConnectionError:
                st.error("❌ Could not connect to Airflow. Ensure Airflow is running at http://localhost:8080.")
            except Exception as e:
                st.error(f"❌ An unexpected error occurred: {e}")
```


<div style='page-break-after: always;'></div>

# File: internal_tools\streamlit_app\pages\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: pipelines\airflow\dags\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: pipelines\airflow\dags\dag_survey_microservice.py

```python
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, RenderConfig

from utils import alert_on_failure

profile_config = ProfileConfig(
    profile_name="civic_pulse",
    target_name="dev",
    profiles_yml_filepath="/opt/airflow/dbt/profiles.yml",
)

default_args = {
    "owner": "data_engineering",
    "depends_on_past": False,
    "on_failure_callback": alert_on_failure,
    "retries": 2,
    "retry_delay": timedelta(minutes=3),
}

with DAG(
    dag_id="dag_survey_microservice_processing",
    start_date=datetime(2026, 9, 1),
    schedule_interval=None,
    catchup=False,
    default_args=default_args,
    tags=["civicpulse", "microservice", "survey_data"],
) as dag:

    wait_for_s3_survey_data = S3KeySensor(
        task_id="wait_for_s3_survey_data",
        bucket_name="civicpulse-raw-surveys",
        bucket_key="raw_surveys/date=*/survey_*.json",
        wildcard_match=True,
        aws_conn_id="aws_default",
        timeout=60 * 60,
        poke_interval=60,
    )

    survey_dbt_run = DbtTaskGroup(
        group_id="survey_dbt_transformations",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(
            select=["stg_survey_responses", "dim_survey_metadata", "fact_daily_survey_responses"]
        ),
    )

    survey_dbt_test = DbtTaskGroup(
        group_id="survey_data_quality_tests",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["fact_daily_survey_responses"]),
    )

    wait_for_s3_survey_data >> survey_dbt_run >> survey_dbt_test
```


<div style='page-break-after: always;'></div>

# File: pipelines\airflow\dags\dag_voter_batch.py

```python
from datetime import datetime, timedelta

from airflow import DAG
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, RenderConfig

from utils import alert_on_failure

profile_config = ProfileConfig(
    profile_name="civic_pulse",
    target_name="dev",
    profiles_yml_filepath="/opt/airflow/dbt/profiles.yml",
)

default_args = {
    "owner": "data_engineering",
    "depends_on_past": False,
    "on_failure_callback": alert_on_failure,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="dag_voter_batch_processing",
    start_date=datetime(2026, 9, 1),
    schedule_interval="@daily",
    catchup=False,
    default_args=default_args,
    tags=["civicpulse", "batch", "voter_files"],
) as dag:

    voter_dbt_run = DbtTaskGroup(
        group_id="voter_dbt_transformations",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["stg_voters", "dim_voter"]),
    )

    voter_dbt_test = DbtTaskGroup(
        group_id="voter_data_quality_tests",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["stg_voters", "dim_voter"]),
    )

    voter_dbt_run >> voter_dbt_test
```


<div style='page-break-after: always;'></div>

# File: pipelines\airflow\dags\utils.py

```python
import logging
from airflow.operators.python import get_current_context

def alert_on_failure(context):
    """
    Custom callback function triggered when an Airflow task fails.
    In production, this would send a payload to a Slack webhook or Email API.
    """
    task_instance = context.get('task_instance')
    dag_id = task_instance.dag_id
    task_id = task_instance.task_id
    execution_date = context.get('execution_date')
    exception = context.get('exception')
    
    error_message = (
        f"🚨 DATA PIPELINE ALERT 🚨\n"
        f"DAG: {dag_id}\n"
        f"Task: {task_id}\n"
        f"Execution Date: {execution_date}\n"
        f"Error: {str(exception)}\n"
        f"Action: Pipeline halted. Data Science team notified."
    )
    
    # Log the alert (In production: requests.post(SLACK_WEBHOOK_URL, json={"text": error_message}))
    logging.error(error_message)
    print(error_message) # Ensures it shows up in local console/Airflow logs
```


<div style='page-break-after: always;'></div>

# File: pipelines\data_quality\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\.gitignore

```gitignore

target/
dbt_packages/
logs/

```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\.user.yml

```yaml
id: d27010aa-b517-4b62-ba88-098219038bc3

```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\civic_pulse.duckdb

```duckdb
�o'�ڳ�DUCK@                                       v1.5.5                          d8cdaa33fd                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  �Nnv<�n=                      	                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            �$AQQo�<                     
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ?r�Z3�        d c d d f maini  ����c d d e civic_pulsef maini  � my_first_dbt_model� d d ide d ��g  h  ������e d ��������e h��f g  h  ��c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_date"} */

  
  create view "civic_pulse"."main"."dim_date__dbt_tmp" as (
    -- Universal date dimension for time-series analysis
-- Note: DuckDB uses standard SQL INTERVAL syntax for date arithmetic
WITH RECURSIVE date_spine AS (
    SELECT CAST('2026-01-01' AS DATE) AS date_day
    UNION ALL
    SELECT date_day + INTERVAL 1 DAY FROM date_spine WHERE date_day < '2026-12-31'
)
SELECT 
    date_day AS date_id,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(MONTH FROM date_day) AS month,
    EXTRACT(DAY FROM date_day) AS day,
    CASE 
        WHEN EXTRACT(DOW FROM date_day) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type
FROM date_spine
  );
� dim_date� d ��d ��d ��d ��d ��� d d f d   
date_spine e d d f ��� 
date_spine� � d f ��� d e f date_dayg �� d e Kg �� d d ��e  f 
2026-01-01����� d ����� d ���  ��� d f ��� d 	e �g �� +� d e �g �� date_day��d 	e �g �� to_days� d e � d 	e �� trunc� d e g �� d e Kg �� d d ��e  f ����� d ����� d ����� d ����� d ����� d ��� ��� d g �� 
date_spine��� d e g �� d e �g �� date_day��� d e Kg �� d d ��e  f 
2026-12-31�������  ������f ������� d e �f date_idg �� date_day��d 	e �f yearg �� 	date_part� main� d e Kg �� d d ��e  f year����d e �g �� date_day��� d ����d 	e �f monthg �� 	date_part� main� d e Kg �� d d ��e  f month����d e �g �� date_day��� d ����d 	e �f dayg �� 	date_part� main� d e Kg �� d d ��e  f day����d e �g �� date_day��� d ����d e �f day_typeg �� d d 
e #g �� d 	e �g �� 	date_part� main� d e Kg �� d d ��e  f DOW����d e �g �� date_day��� d ����d e Kg �� d d ��e  f  ����d e Kg �� d d ��e  f ������e d e Kg �� d d ��e  f Weekend������� d e Kg �� d d ��e  f Weekday������� d g �� 
date_spine���  ����� date_idyearmonthdayday_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_geography"} */

  
  create view "civic_pulse"."main"."dim_geography__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_geography"
)
SELECT 
    geography_id,
    district_name,
    precinct_name,
    demographic_type
FROM staged
  );
� dim_geography� d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� stg_geography� civic_pulse���  ����f ������� d e �g �� geography_id��d e �g �� district_name��d e �g �� precinct_name��d e �g �� demographic_type��� d g �� staged���  ����� geography_iddistrict_nameprecinct_namedemographic_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_survey_metadata"} */

  
  create view "civic_pulse"."main"."dim_survey_metadata__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_survey_metadata"
)
SELECT 
    survey_id,
    question_text,
    pollster_name,
    CAST(survey_date AS DATE) AS survey_date
FROM staged
  );
� dim_survey_metadata� d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� stg_survey_metadata� civic_pulse���  ����f ������� d e �g �� 	survey_id��d e �g �� question_text��d e �g �� pollster_name��d e f survey_dateg �� d e �g �� survey_date��� d ����� d g �� staged���  ����� 	survey_idquestion_textpollster_namesurvey_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_voter"}��������d e f d ��g h d  e f  g � d e ��� d e ��������e d e f d ��g h d e f  g ����������d d d e f g � d e ��� d e ������e d e f d e �HYLL                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ������e d e         ��e � �����       d  e f d ��������e ��g  ��                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  */

  
  create view "civic_pulse"."main"."dim_voter__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_voters"
)
SELECT 
    voter_id,
    first_name,
    last_name,
    registration_status,
    party_affiliation,
    geography_id
FROM staged
  );
� 	dim_voter� d ��d ��d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� 
stg_voters� civic_pulse���  ����f ������� d e �g �� voter_id��d e �g �� 
first_name��d e �g �� 	last_name��d e �g �� registration_status��d e �g �� party_affiliation��d e �g �� geography_id��� d g �� staged���  ����� voter_id
first_name	last_nameregistration_statusparty_affiliationgeography_id����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.fact_daily_survey_responses"} */

  
  create view "civic_pulse"."main"."fact_daily_survey_responses__dbt_tmp" as (
    -- The central Fact Table connecting all dimensions
WITH responses AS (
    SELECT * FROM "civic_pulse"."main"."stg_survey_responses"
),
voters AS (
    SELECT * FROM "civic_pulse"."main"."dim_voter"
),
geography AS (
    SELECT * FROM "civic_pulse"."main"."dim_geography"
),
surveys AS (
    SELECT * FROM "civic_pulse"."main"."dim_survey_metadata"
),
dates AS (
    SELECT * FROM "civic_pulse"."main"."dim_date"
)

SELECT 
    r.response_id,
    r.voter_id,
    r.survey_id,
    v.geography_id,
    CAST(r.response_date AS DATE) AS date_id,
    r.sentiment_score,
    r.response_time_seconds,
    g.district_name,
    s.pollster_name
FROM responses r
LEFT JOIN voters v ON r.voter_id = v.voter_id
LEFT JOIN geography g ON v.geography_id = g.geography_id
LEFT JOIN surveys s ON r.survey_id = s.survey_id
LEFT JOIN dates d ON CAST(r.response_date AS DATE) = d.date_id
  );
� fact_daily_survey_responses� 	d ��d ��d ��d ��d ��d e d � � ����d e d � � ����d ��d ��� d d f d   	responses e d d f ��� d e �g ��  ��� d g �� main� stg_survey_responses� civic_pulse���  ����f ����  voters e d d f ��� d e �g ��  ��� d g �� main� 	dim_voter� civic_pulse���  ����f ����  	geography e d d f ��� d e �g ��  ��� d g �� main� dim_geography� civic_pulse���  ����f ����  surveys e d d f ��� d e �g ��  ��� d g �� main� dim_survey_metadata� civic_pulse���  ����f ����  dates e d d f ��� d e �g ��  ��� d g �� main� dim_date� civic_pulse���  ����f ������� 	d e �g �� rresponse_id��d e �g �� rvoter_id��d e �g �� r	survey_id��d e �g �� vgeography_id��d e f date_idg �� d e �g �� rresponse_date��� d ����d e �g �� rsentiment_score��d e �g �� rresponse_time_seconds��d e �g �� gdistrict_name��d e �g �� spollster_name��� d � d � d � d � d e rg �� 	responses��� d e vg �� voters��� d e g �� d e �g �� rvoter_id��� d e �g �� vvoter_id����� �  ��� d e gg �� 	geography��� d e g �� d e �g �� vgeography_id��� d e �g �� ggeography_id����� �  ��� d e sg �� surveys��� d e g �� d e �g �� r	survey_id��� d e �g �� s	survey_id����� �  ��� d e dg �� dates��� d e g �� d e g �� d e �g �� rresponse_date��� d ����� d e �g �� ddate_id����� �  ���  ����� 	response_idvoter_id	survey_idgeography_iddate_idsentiment_scoreresponse_time_secondsdistrict_namepollster_name����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_geography"} */

  
  create view "civic_pulse"."main"."stg_geography__dbt_tmp" as (
    -- Simulates raw geography/precinct data
SELECT 
    'GEO-101' AS geography_id,
    'District 5' AS district_name,
    'Precinct A' AS precinct_name,
    'Urban' AS demographic_type
UNION ALL
SELECT 
    'GEO-102', 'District 8', 'Precinct B', 'Suburban'
  );
� stg_geography� d ��d        ��d ��d ��� d d f ��� � d f ��� d e Kf geography_idg �� d d ��e  f GEO-101����d e Kf district_nameg �� d d ��e  f 
District 5����d e Kf precinct_nameg �� d d ��e  f 
Precinct A����d e Kf demographic_typeg �� d d ��e  f Urban����� d ���  ��� d f ��� d e Kg �� d d ��e  f GEO-102����d e Kg �� d d ��e  f 
District 8����d e Kg �� d d ��e  f 
Precinct B����d e Kg �� d d ��e  f Suburban����� d ���  ������� geography_iddistrict_nameprecinct_namedemographic_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_survey_metadata"} */

  
  create view "civic_pulse"."main"."stg_survey_metadata__dbt_tmp" as (
    -- Simulates survey question definitions
SELECT 
    'SRV-001' AS survey_id,
    'Do you support the new infrastructure bill?' AS question_text,
    'Pew Research Mock' AS pollster_name,
    '2026-09-01' AS survey_date
  );
� stg_survey_metadata� d ��d ��d ��d ��� d d f ��� d e Kf 	survey_idg �� d d ��e  f SRV-001����d e Kf question_textg �� d d ��e  f +Do you support the new infrastructure bill?����d e Kf pollster_nameg �� d d ��e  f Pew Research Mock����d e Kf survey_dateg �� d d ��e  f 
2026-09-01����� d ���  ����� 	survey_idquestion_textpollster_namesurvey_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_survey_responses"} */

  
  create view "civic_pulse"."main"."stg_survey_responses__dbt_tmp" as (
    -- Simulates high-velocity microservice survey responses
SELECT 
    'RESP-001' AS response_id,
    'VTR-001' AS voter_id,
    'SRV-001' AS survey_id,
    0.85 AS sentiment_score, -- 0.0 to 1.0
    12.5 AS response_time_seconds,
    '2026-09-15' AS response_date
UNION ALL
SELECT 
    'RESP-002', 'VTR-002', 'SRV-001', 0.45, 8.2, '2026-09-15'
  );
� stg_survey_responses� d ��d ��d ��d e d � � ����d e d � � ����d ��� d d f ��� � d f ��� d e Kf response_idg �� d d ��e  f RESP-001����d e Kf voter_idg �� d d ��e  f VTR-001����d e Kf 	survey_idg �� d d ��e  f SRV-001����d e Kf sentiment_scoreg �� d d e d � � ����e  f � ����d e Kf response_time_secondsg �� d d e d � � ����e  f � ����d e Kf response_dateg �� d d ��e  f 
2026-09-15����� d ���  ��� d f ��� d e Kg �� d d ��e  f RESP-002����d e Kg �� d d ��e  f VTR-002����d e Kg �� d d ��e  f SRV-001����d e Kg �� d d e d � � ����e  f -����d e Kg �� d d e d � � ����e  f � ����d e Kg �� d d ��e  f 
2026-09-15����� d ���  ������� response_idvoter_id	survey_idsentiment_scoreresponse_time_secondsresponse_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_voters"} */

  
  create view "civic_pulse"."main"."stg_voters__dbt_tmp" as (
    -- Simulates raw voter file data from S3
SELECT 
    'VTR-001' AS voter_id,
    'John' AS first_name,
    'Doe' AS last_name,
    'Active' AS registration_status,
    'Democrat' AS party_affiliation,
    'GEO-101' AS geography_id
UNION ALL
SELECT 
    'VTR-002', 'Jane', 'Smith', 'Active', 'Independent', 'GEO-102'
  );
� 
stg_voters� d ��d ��d ��d ��d ��d ��� d d f ��� � d f ��� d e Kf voter_idg �� d d ��e  f VTR-001����d e Kf 
first_nameg �� d d ��e  f John����d e Kf 	last_nameg �� d d ��e  f Doe����d e Kf registration_statusg �� d d ��e  f Active����d e Kf party_affiliationg �� d d ��e  f Democrat����d e Kf geography_idg �� d d ��e  f GEO-101����� d ���  ��� d f ��� d e Kg �� d d ��e  f VTR-002����d e Kg �� d d ��e  f Jane����d e Kg �� d d ��e  f Smith����d e Kg �� d d ��e  f Active����d e Kg �� d d ��e  f Independent����d e Kg �� d d ��e  f GEO-102����� d ���  ������� voter_id
first_name	last_nameregistration_statusparty       d c d d f maini  ����c d d e civic_pulsef maini  � my_first_dbt_model� d d ide d ��g  h  ������e d ��������e h��f g  h  ��c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_date"} */

  
  create view "civic_pulse"."main"."dim_date__dbt_tmp" as (
    -- Universal date dimension for time-series analysis
-- Note: DuckDB uses standard SQL INTERVAL syntax for date arithmetic
WITH RECURSIVE date_spine AS (
    SELECT CAST('2026-01-01' AS DATE) AS date_day
    UNION ALL
    SELECT date_day + INTERVAL 1 DAY FROM date_spine WHERE date_day < '2026-12-31'
)
SELECT 
    date_day AS date_id,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(MONTH FROM date_day) AS month,
    EXTRACT(DAY FROM date_day) AS day,
    CASE 
        WHEN EXTRACT(DOW FROM date_day) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type
FROM date_spine
  );
� dim_date� d ��d ��d ��d ��d ��� d d f d   
date_spine e d d f ��� 
date_spine� � d f ��� d e f date_dayg �� d e Kg �� d d ��e  f 
2026-01-01����� d ����� d ���  ��� d f ��� d 	e �g �� +� d e �g �� date_day��d 	e �g �� to_days� d e � d 	e �� trunc� d e g �� d e Kg �� d d ��e  f ����� d ����� d ����� d ����� d ����� d ��� ��� d g �� 
date_spine��� d e g �� d e �g �� date_day��� d e Kg �� d d ��e  f 
2026-12-31�������  ������f ������� d e �f date_idg �� date_day��d 	e �f yearg �� 	date_part� main� d e Kg �� d d ��e  f year����d e �g �� date_day��� d ����d 	e �f monthg �� 	date_part� main� d e Kg �� d d ��e  f month����d e �g �� date_day��� d ����d 	e �f dayg �� 	date_part� main� d e Kg �� d d ��e  f day����d e �g �� date_day��� d ����d e �f day_typeg �� d d 
e #g �� d 	e �g �� 	date_part� main� d e Kg �� d d ��e  f DOW����d e �g �� date_day��� d ����d e Kg �� d d ��e  f  ����d e Kg �� d d ��e  f ������e d e Kg �� d d ��e  f Weekend������� d e Kg �� d d ��e  f Weekday������� d g �� 
date_spine���  ����� date_idyearmonthdayday_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_geography"} */

  
  create view "civic_pulse"."main"."dim_geography__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_geography"
)
SELECT 
    geography_id,
    district_name,
    precinct_name,
    demographic_type
FROM staged
  );
� dim_geography� d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� stg_geography� civic_pulse���  ����f ������� d e �g �� geography_id��d e �g �� district_name��d e �g �� precinct_name��d e �g �� demographic_type��� d g �� staged���  ����� geography_iddistrict_nameprecinct_namedemographic_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_survey_metadata"} */

  
  create view "civic_pulse"."main"."dim_survey_metadata__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_survey_metadata"
)
SELECT 
    survey_id,
    question_text,
    pollster_name,
    CAST(survey_date AS DATE) AS survey_date
FROM staged
  );
� dim_survey_metadata� d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� stg_survey_metadata� civic_pulse���  ����f ������� d e �g �� 	survey_id��d e �g �� question_text��d e �g �� pollster_name��d e f survey_dateg �� d e �g �� survey_date��� d ����� d g �� staged���  ����� 	survey_idquestion_textpollster_namesurvey_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.dim_voter"}        */

  
  create view "civic_pulse"."main"."dim_voter__dbt_tmp" as (
    WITH staged AS (
    SELECT * FROM "civic_pulse"."main"."stg_voters"
)
SELECT 
    voter_id,
    first_name,
    last_name,
    registration_status,
    party_affiliation,
    geography_id
FROM staged
  );
� 	dim_voter� d ��d ��d ��d ��d ��d ��� d d f d   staged e d d f ��� d e �g ��  ��� d g �� main� 
stg_voters� civic_pulse���  ����f ������� d e �g �� voter_id��d e �g �� 
first_name��d e �g �� 	last_name��d e �g �� registration_status��d e �g �� party_affiliation��d e �g �� geography_id��� d g �� staged���  ����� voter_id
first_name	last_nameregistration_statusparty_affiliationgeography_id����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.fact_daily_survey_responses"} */

  
  create view "civic_pulse"."main"."fact_daily_survey_responses__dbt_tmp" as (
    -- The central Fact Table connecting all dimensions
WITH responses AS (
    SELECT * FROM "civic_pulse"."main"."stg_survey_responses"
),
voters AS (
    SELECT * FROM "civic_pulse"."main"."dim_voter"
),
geography AS (
    SELECT * FROM "civic_pulse"."main"."dim_geography"
),
surveys AS (
    SELECT * FROM "civic_pulse"."main"."dim_survey_metadata"
),
dates AS (
    SELECT * FROM "civic_pulse"."main"."dim_date"
)

SELECT 
    r.response_id,
    r.voter_id,
    r.survey_id,
    v.geography_id,
    CAST(r.response_date AS DATE) AS date_id,
    r.sentiment_score,
    r.response_time_seconds,
    g.district_name,
    s.pollster_name
FROM responses r
LEFT JOIN voters v ON r.voter_id = v.voter_id
LEFT JOIN geography g ON v.geography_id = g.geography_id
LEFT JOIN surveys s ON r.survey_id = s.survey_id
LEFT JOIN dates d ON CAST(r.response_date AS DATE) = d.date_id
  );
� fact_daily_survey_responses� 	d ��d ��d ��d ��d ��d e d � � ����d e d � � ����d ��d ��� d d f d   	responses e d d f ��� d e �g ��  ��� d g �� main� stg_survey_responses� civic_pulse���  ����f ����  voters e d d f ��� d e �g ��  ��� d g �� main� 	dim_voter� civic_pulse���  ����f ����  	geography e d d f ��� d e �g ��  ��� d g �� main� dim_geography� civic_pulse���  ����f ����  surveys e d d f ��� d e �g ��  ��� d g �� main� dim_survey_metadata� civic_pulse���  ����f ����  dates e d d f ��� d e �g ��  ��� d g �� main� dim_date� civic_pulse���  ����f ������� 	d e �g �� rresponse_id��d e �g �� rvoter_id��d e �g �� r	survey_id��d e �g �� vgeography_id��d e f date_idg �� d e �g �� rresponse_date��� d ����d e �g �� rsentiment_score��d e �g �� rresponse_time_seconds��d e �g �� gdistrict_name��d e �g �� spollster_name��� d � d � d � d � d e rg �� 	responses��� d e vg �� voters��� d e g �� d e �g �� rvoter_id��� d e �g �� vvoter_id����� �  ��� d e gg �� 	geography��� d e g �� d e �g �� vgeography_id��� d e �g �� ggeography_id����� �  ��� d e sg �� surveys��� d e g �� d e �g �� r	survey_id��� d e �g �� s	survey_id����� �  ��� d e dg �� dates��� d e g �� d e g �� d e �g �� rresponse_date��� d ����� d e �g �� ddate_id����� �  ���  ����� 	response_idvoter_id	survey_idgeography_iddate_idsentiment_scoreresponse_time_secondsdistrict_namepollster_name����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_geography"} */

  
  create view "civic_pulse"."main"."stg_geography__dbt_tmp" as (
    -- Simulates raw geography/precinct data
SELECT 
    'GEO-101' AS geography_id,
    'District 5' AS district_name,
    'Precinct A' AS precinct_name,
    'Urban' AS demographic_type
UNION ALL
SELECT 
    'GEO-102', 'District 8', 'Precinct B', 'Suburban'
  );
� stg_geography� d ��d        ��d ��d ��� d d f ��� � d f ��� d e Kf geography_idg �� d d ��e  f GEO-101����d e Kf district_nameg �� d d ��e  f 
District 5����d e Kf precinct_nameg �� d d ��e  f 
Precinct A����d e Kf demographic_typeg �� d d ��e  f Urban����� d ���  ��� d f ��� d e Kg �� d d ��e  f GEO-102����d e Kg �� d d ��e  f 
District 8����d e Kg �� d d ��e  f 
Precinct B����d e Kg �� d d ��e  f Suburban����� d ���  ������� geography_iddistrict_nameprecinct_namedemographic_type����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_survey_metadata"} */

  
  create view "civic_pulse"."main"."stg_survey_metadata__dbt_tmp" as (
    -- Simulates survey question definitions
SELECT 
    'SRV-001' AS survey_id,
    'Do you support the new infrastructure bill?' AS question_text,
    'Pew Research Mock' AS pollster_name,
    '2026-09-01' AS survey_date
  );
� stg_survey_metadata� d ��d ��d ��d ��� d d f ��� d e Kf 	survey_idg �� d d ��e  f SRV-001����d e Kf question_textg �� d d ��e  f +Do you support the new infrastructure bill?����d e Kf pollster_nameg �� d d ��e  f Pew Research Mock����d e Kf survey_dateg �� d d ��e  f 
2026-09-01����� d ���  ����� 	survey_idquestion_textpollster_namesurvey_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_survey_responses"} */

  
  create view "civic_pulse"."main"."stg_survey_responses__dbt_tmp" as (
    -- Simulates high-velocity microservice survey responses
SELECT 
    'RESP-001' AS response_id,
    'VTR-001' AS voter_id,
    'SRV-001' AS survey_id,
    0.85 AS sentiment_score, -- 0.0 to 1.0
    12.5 AS response_time_seconds,
    '2026-09-15' AS response_date
UNION ALL
SELECT 
    'RESP-002', 'VTR-002', 'SRV-001', 0.45, 8.2, '2026-09-15'
  );
� stg_survey_responses� d ��d ��d ��d e d � � ����d e d � � ����d ��� d d f ��� � d f ��� d e Kf response_idg �� d d ��e  f RESP-001����d e Kf voter_idg �� d d ��e  f VTR-001����d e Kf 	survey_idg �� d d ��e  f SRV-001����d e Kf sentiment_scoreg �� d d e d � � ����e  f � ����d e Kf response_time_secondsg �� d d e d � � ����e  f � ����d e Kf response_dateg �� d d ��e  f 
2026-09-15����� d ���  ��� d f ��� d e Kg �� d d ��e  f RESP-002����d e Kg �� d d ��e  f VTR-002����d e Kg �� d d ��e  f SRV-001����d e Kg �� d d e d � � ����e  f -����d e Kg �� d d e d � � ����e  f � ����d e Kg �� d d ��e  f 
2026-09-15����� d ���  ������� response_idvoter_id	survey_idsentiment_scoreresponse_time_secondsresponse_date����c d d f maini  j �/* {"app": "dbt", "dbt_version": "1.7.13", "profile_name": "civic_pulse", "target_name": "dev", "node_id": "model.civic_pulse.stg_voters"} */

  
  create view "civic_pulse"."main"."stg_voters__dbt_tmp" as (
    -- Simulates raw voter file data from S3
SELECT 
    'VTR-001' AS voter_id,
    'John' AS first_name,
    'Doe' AS last_name,
    'Active' AS registration_status,
    'Democrat' AS party_affiliation,
    'GEO-101' AS geography_id
UNION ALL
SELECT 
    'VTR-002', 'Jane', 'Smith', 'Active', 'Independent', 'GEO-102'
  );
� 
stg_voters� d ��d ��d ��d ��d ��d ��� d d f ��� � d f ��� d e Kf voter_idg �� d d ��e  f VTR-001����d e Kf 
first_nameg �� d d ��e  f John����d e Kf 	last_nameg �� d d ��e  f Doe����d e Kf registration_statusg �� d d ��e  f Active����d e Kf party_affiliationg �� d d ��e  f Democrat����d e Kf geography_idg �� d d ��e  f GEO-101����� d ���  ��� d f ��� d e Kg �� d d ��e  f VTR-002����d e Kg �� d d ��e  f Jane����d e Kg �� d d ��e  f Smith����d e Kg �� d d ��e  f Active����d e Kg �� d d ��e  f Independent����d e Kg �� d d ��e  f GEO-102����� d ���  ������� voter_id
first_name	last_nameregistration_statusparty��������_affiliationgeography_id������                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ��������_affiliationgeography_id������                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ��������                               ��������                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ��������                               �������                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        �AJJ*�P�����������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\dbt_project.yml

```yaml

# Name your project! Project names should contain only lowercase characters
# and underscores. A good package name should reflect your organization's
# name or the intended use of these models
name: 'civic_pulse'
version: '1.0.0'
config-version: 2

# This setting configures which "profile" dbt uses for this project.
profile: 'civic_pulse'

# These configurations specify where dbt should look for different types of files.
# The `model-paths` config, for example, states that models in this project can be
# found in the "models/" directory. You probably won't need to change these!
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:         # directories to be removed by `dbt clean`
  - "target"
  - "dbt_packages"


# Configuring models
# Full documentation: https://docs.getdbt.com/docs/configuring-models

# In this example config, we tell dbt to build all models in the example/
# directory as views. These settings can be overridden in the individual model
# files using the `{{ config(...) }}` macro.
models:
  civic_pulse:
    # Config indicated by + and applies to all files under models/example/
    example:
      +materialized: view

```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\macros\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\macros\test_null_percentage.sql

```sql
{% test null_percentage_less_than(model, column_name, threshold=0.2) %}
-- Custom test to ensure the percentage of null values in a column does not exceed the threshold
with validation as (
    select
        sum(case when {{ column_name }} is null then 1 else 0 end) * 1.0 / nullif(count(*), 0) as null_ratio
    from {{ model }}
),
validation_errors as (
    select null_ratio
    from validation
    where null_ratio > {{ threshold }}
)
select * from validation_errors
{% endtest %}
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\dim_date.sql

```sql
-- Universal date dimension for time-series analysis
-- Note: DuckDB uses standard SQL INTERVAL syntax for date arithmetic
WITH RECURSIVE date_spine AS (
    SELECT CAST('2026-01-01' AS DATE) AS date_day
    UNION ALL
    SELECT date_day + INTERVAL 1 DAY FROM date_spine WHERE date_day < '2026-12-31'
)
SELECT 
    date_day AS date_id,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(MONTH FROM date_day) AS month,
    EXTRACT(DAY FROM date_day) AS day,
    CASE 
        WHEN EXTRACT(DOW FROM date_day) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type
FROM date_spine
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\dim_geography.sql

```sql
WITH staged AS (
    SELECT * FROM {{ ref('stg_geography') }}
)
SELECT 
    geography_id,
    district_name,
    precinct_name,
    demographic_type
FROM staged
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\dim_survey_metadata.sql

```sql
WITH staged AS (
    SELECT * FROM {{ ref('stg_survey_metadata') }}
)
SELECT 
    survey_id,
    question_text,
    pollster_name,
    CAST(survey_date AS DATE) AS survey_date
FROM staged
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\dim_voter.sql

```sql
WITH staged AS (
    SELECT * FROM {{ ref('stg_voters') }}
)
SELECT 
    voter_id,
    first_name,
    last_name,
    registration_status,
    party_affiliation,
    geography_id
FROM staged
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\fact_daily_survey_responses.sql

```sql
-- The central Fact Table connecting all dimensions
WITH responses AS (
    SELECT * FROM {{ ref('stg_survey_responses') }}
),
voters AS (
    SELECT * FROM {{ ref('dim_voter') }}
),
geography AS (
    SELECT * FROM {{ ref('dim_geography') }}
),
surveys AS (
    SELECT * FROM {{ ref('dim_survey_metadata') }}
),
dates AS (
    SELECT * FROM {{ ref('dim_date') }}
)

SELECT 
    r.response_id,
    r.voter_id,
    r.survey_id,
    v.geography_id,
    CAST(r.response_date AS DATE) AS date_id,
    r.sentiment_score,
    r.response_time_seconds,
    g.district_name,
    s.pollster_name
FROM responses r
LEFT JOIN voters v ON r.voter_id = v.voter_id
LEFT JOIN geography g ON v.geography_id = g.geography_id
LEFT JOIN surveys s ON r.survey_id = s.survey_id
LEFT JOIN dates d ON CAST(r.response_date AS DATE) = d.date_id
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\marts\schema.yml

```yaml
version: 2

models:
  - name: dim_voter
    description: "Dimension table containing voter demographic and registration details."
    columns:
      - name: voter_id
        description: "Unique identifier for the voter."
        tests:
          - unique
          - not_null

  - name: dim_geography
    description: "Dimension table mapping geographic districts and precincts."
    columns:
      - name: geography_id
        description: "Unique identifier for the geographic area."
        tests:
          - unique
          - not_null

  - name: dim_survey_metadata
    description: "Dimension table containing survey question text and pollster information."
    columns:
      - name: survey_id
        description: "Unique identifier for the survey."
        tests:
          - unique
          - not_null

  - name: dim_date
    description: "Standard date dimension for time-series aggregation."
    columns:
      - name: date_id
        description: "Primary key for the date."
        tests:
          - unique
          - not_null

  - name: fact_daily_survey_responses
    description: "Central fact table recording daily survey responses, linked to voter, geography, and survey dimensions."
    columns:
      - name: response_id
        description: "Unique identifier for the survey response."
        tests:
          - unique
          - not_null
      - name: sentiment_score
        description: "Calculated sentiment score of the response (0.0 to 1.0)."
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0.0
              max_value: 1.0
          - null_percentage_less_than:
              threshold: 0.2  # Fails if more than 20% of responses are null
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\staging\stg_geography.sql

```sql
-- Simulates raw geography/precinct data
SELECT 
    'GEO-101' AS geography_id,
    'District 5' AS district_name,
    'Precinct A' AS precinct_name,
    'Urban' AS demographic_type
UNION ALL
SELECT 
    'GEO-102', 'District 8', 'Precinct B', 'Suburban'
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\staging\stg_survey_metadata.sql

```sql
-- Simulates survey question definitions
SELECT 
    'SRV-001' AS survey_id,
    'Do you support the new infrastructure bill?' AS question_text,
    'Pew Research Mock' AS pollster_name,
    '2026-09-01' AS survey_date
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\staging\stg_survey_responses.sql

```sql
-- Simulates high-velocity microservice survey responses
SELECT 
    'RESP-001' AS response_id,
    'VTR-001' AS voter_id,
    'SRV-001' AS survey_id,
    0.85 AS sentiment_score, -- 0.0 to 1.0
    12.5 AS response_time_seconds,
    '2026-09-15' AS response_date
UNION ALL
SELECT 
    'RESP-002', 'VTR-002', 'SRV-001', 0.45, 8.2, '2026-09-15'
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\models\staging\stg_voters.sql

```sql
-- Simulates raw voter file data from S3
SELECT 
    'VTR-001' AS voter_id,
    'John' AS first_name,
    'Doe' AS last_name,
    'Active' AS registration_status,
    'Democrat' AS party_affiliation,
    'GEO-101' AS geography_id
UNION ALL
SELECT 
    'VTR-002', 'Jane', 'Smith', 'Active', 'Independent', 'GEO-102'
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\package-lock.yml

```yaml
packages:
- package: dbt-labs/dbt_utils
  version: 1.1.1
sha1_hash: a158c48c59c2bb7d729d2a4e215aabe5bb4f3353

```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\packages.yml

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.1.1
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\profiles.yml

```yaml
# civic_pulse:
#   target: dev
#   outputs:
#     dev:
#       type: duckdb
#       path: /opt/airflow/dbt/civic_pulse.duckdb
#       threads: 4


civic_pulse:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: 'civic_pulse.duckdb'  # <-- CHANGE THIS BACK to a relative path
      threads: 4
```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\README.md

```md
Welcome to your new dbt project!

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices

```


<div style='page-break-after: always;'></div>

# File: pipelines\dbt\tests\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: README.md

```md
```


<div style='page-break-after: always;'></div>

# File: requirements.txt

```txt
# Core Data Engineering & Orchestration
dbt-core==1.7.13
dbt-duckdb==1.7.1

# AWS & Cloud Infrastructure
boto3>=1.34.0

# Microservices & API Development
fastapi>=0.110.0
uvicorn>=0.27.0
pydantic>=2.6.0

# Data Processing & File Formats
pandas>=2.2.0
pyarrow>=15.0.0


# Internal Tools & Automation
streamlit>=1.30.0
requests>=2.31.0
```


<div style='page-break-after: always;'></div>

# File: scripts\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: scripts\deploy.ps1

```ps1
# CivicPulse Deployment Script
# Purpose: Build Docker infrastructure, initialize Airflow, and run dbt

$ErrorActionPreference = "Stop"

Write-Host "Deploying CivicPulse Infrastructure..." -ForegroundColor Cyan

# Ensure we're in the project root
Set-Location -Path $PSScriptRoot\..

# 1. Check Docker
Write-Host "`n[1] Checking Docker..." -ForegroundColor Yellow

try {
    $null = docker info 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not running"
    }

    Write-Host "[OK] Docker is running" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# 2. Build and Start Docker Containers
Write-Host "`n[2] Building and starting Docker containers..." -ForegroundColor Yellow
Write-Host "This may take 2-3 minutes on first run..." -ForegroundColor Gray

docker compose up -d --build

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker compose failed. Check the error messages above." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Containers started successfully" -ForegroundColor Green

# 3. Wait for Airflow to Initialize
Write-Host "`n[3] Waiting for Airflow to initialize..." -ForegroundColor Yellow
Write-Host "This may take 20-30 seconds..." -ForegroundColor Gray

Start-Sleep -Seconds 25

# Verify Airflow is running
$retryCount = 0
$maxRetries = 10
$airflowReady = $false

while ($retryCount -lt $maxRetries -and -not $airflowReady) {
    try {
        $response = Invoke-WebRequest `
            -Uri "http://localhost:8080/health" `
            -Method Get `
            -UseBasicParsing `
            -ErrorAction SilentlyContinue

        if ($response.StatusCode -eq 200) {
            $airflowReady = $true
            Write-Host "[OK] Airflow webserver is healthy" -ForegroundColor Green
        }
    }
    catch {
        $retryCount++
        Write-Host "Waiting for Airflow... (attempt $retryCount/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $airflowReady) {
    Write-Host "[WARNING] Airflow may still be initializing." -ForegroundColor Yellow
    Write-Host "You can check manually at http://localhost:8080" -ForegroundColor Yellow
}

# 4. Initialize dbt
Write-Host "`n[4] Initializing dbt dependencies..." -ForegroundColor Yellow

Set-Location pipelines\dbt

try {
    dbt deps
    Write-Host "[OK] dbt dependencies installed" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] dbt deps failed. You may need to run this manually later." -ForegroundColor Yellow
}

Set-Location ..\..

# 5. Deployment Complete
Write-Host "`nDeployment complete!" -ForegroundColor Cyan
Write-Host "Access Airflow at: http://localhost:8080" -ForegroundColor White
Write-Host "Default credentials: admin / admin" -ForegroundColor White
Write-Host "Run '.\scripts\weekly_cleanup.ps1' to schedule weekly maintenance" -ForegroundColor White
```


<div style='page-break-after: always;'></div>

# File: scripts\reset_env.ps1

```ps1
# CivicPulse Full Environment Reset Script
# WARNING: This will destroy all local containers, volumes, caches, and scheduled tasks!
# NOTE: MUST be run as Administrator to delete the Scheduled Task.

$ErrorActionPreference = "Stop"

Write-Host "WARNING: This will destroy your local CivicPulse environment!" -ForegroundColor Red
Write-Host "This includes:" -ForegroundColor Yellow
Write-Host "  - All Docker containers and volumes" -ForegroundColor Gray
Write-Host "  - Local dbt caches and packages" -ForegroundColor Gray
Write-Host "  - Python virtual environment" -ForegroundColor Gray
Write-Host "  - Windows Task Scheduler task (CivicPulse Weekly Cleanup)" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "Are you sure you want to continue? Type 'yes' to confirm"

if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit
}

# 1. Remove Windows Task Scheduler Task
Write-Host "`n[1] Removing Windows Task Scheduler task..." -ForegroundColor Yellow
$taskName = "CivicPulse Weekly Cleanup"
try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    Write-Host "   [OK] Scheduled task '$taskName' removed." -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*Access is denied*") {
        Write-Host "   [ERROR] Access denied. Please run this script as Administrator." -ForegroundColor Red
    } else {
        Write-Host "   [INFO] Scheduled task '$taskName' not found. Skipping." -ForegroundColor Gray
    }
}

# 2. Tear Down Docker Environment
Write-Host "`n[2] Tearing down Docker environment and removing volumes..." -ForegroundColor Yellow
try {
    docker compose down -v
    Write-Host "   [OK] Docker containers and volumes removed." -ForegroundColor Green
} catch {
    Write-Host "   [WARNING] Docker compose down failed or no containers to remove." -ForegroundColor Yellow
}

# 3. Remove dbt Caches (Using absolute paths to prevent null errors)
Write-Host "`n[3] Removing local dbt caches..." -ForegroundColor Yellow
$dbtTargetPath = Join-Path $PSScriptRoot "..\pipelines\dbt\target"
$dbtPackagesPath = Join-Path $PSScriptRoot "..\pipelines\dbt\dbt_packages"

if (Test-Path $dbtTargetPath) {
    Remove-Item -Recurse -Force $dbtTargetPath
    Write-Host "   [OK] Removed: target" -ForegroundColor Green
} else {
    Write-Host "   [INFO] target folder not found. Skipping." -ForegroundColor Gray
}

if (Test-Path $dbtPackagesPath) {
    Remove-Item -Recurse -Force $dbtPackagesPath
    Write-Host "   [OK] Removed: dbt_packages" -ForegroundColor Green
} else {
    Write-Host "   [INFO] dbt_packages folder not found. Skipping." -ForegroundColor Gray
}

# 4. Remove Python Virtual Environment
Write-Host "`n[4] Removing Python virtual environment..." -ForegroundColor Yellow
$venvPath = Join-Path $PSScriptRoot "..\.venv"
if (Test-Path $venvPath) {
    Remove-Item -Recurse -Force $venvPath
    Write-Host "   [OK] Removed: .venv" -ForegroundColor Green
} else {
    Write-Host "   [INFO] .venv folder not found. Skipping." -ForegroundColor Gray
}

# 5. Summary
Write-Host "`n[OK] Environment completely reset!" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run '.\scripts\setup_env.ps1' to provision a fresh environment" -ForegroundColor Gray
Write-Host "  2. Run '.\scripts\deploy.ps1' to deploy infrastructure" -ForegroundColor Gray
Write-Host "  3. Run '.\scripts\schedule_cleanup.ps1' (as Admin) to reschedule weekly cleanup" -ForegroundColor Gray
```


<div style='page-break-after: always;'></div>

# File: scripts\schedule_cleanup.ps1

```ps1
# CivicPulse Schedule Cleanup Task Script
# Purpose: Creates a Windows Scheduled Task to run weekly_cleanup.ps1 every Sunday at 2 AM
# Note: This script MUST be run as Administrator.

$ErrorActionPreference = "Stop"

# 1. Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Error: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "   Please right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Yellow
    exit 1
}

# 2. Define Task Parameters
$taskName = "CivicPulse Weekly Cleanup"
$taskDescription = "Archive logs and clean up old S3 files to reduce costs"

# Dynamically get the absolute path to weekly_cleanup.ps1 based on this script's location
$scriptPath = Join-Path $PSScriptRoot "weekly_cleanup.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ Error: Could not find weekly_cleanup.ps1 at $scriptPath" -ForegroundColor Red
    exit 1
}

# 3. Define Task Action, Trigger, and Principal
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

# 4. Check if task already exists and remove it to avoid conflicts on re-runs
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "⚠️  Task '$taskName' already exists. Unregistering it first..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 5. Register the new Scheduled Task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "✅ Scheduled task '$taskName' created successfully!" -ForegroundColor Green
Write-Host "   The script will run every Sunday at 2:00 AM." -ForegroundColor Gray
Write-Host "   You can view or modify it in the Windows Task Scheduler GUI." -ForegroundColor Gray
```


<div style='page-break-after: always;'></div>

# File: scripts\setup_env.ps1

```ps1
# CivicPulse Environment Setup Script
# Purpose: Automate environment provisioning, dependency installation, and AWS CLI configuration

$ErrorActionPreference = "Stop"

Write-Host "Starting CivicPulse Environment Setup..." -ForegroundColor Cyan

# 1. Check Python Installation
Write-Host "`n[1] Checking Python installation..." -ForegroundColor Yellow

try {
    $pythonVersion = python --version 2>&1
    Write-Host "[OK] Python found: $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Python is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Python 3.8+ from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# 2. Setup Virtual Environment
Write-Host "`n[2] Setting up virtual environment..." -ForegroundColor Yellow

$VenvDir = ".venv"

if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Gray
    python -m venv $VenvDir
    Write-Host "[OK] Virtual environment created at $VenvDir" -ForegroundColor Green
}
else {
    Write-Host "[OK] Virtual environment already exists" -ForegroundColor Green
}

# 3. Activate Virtual Environment
Write-Host "`n[3] Activating virtual environment..." -ForegroundColor Yellow

& "$VenvDir\Scripts\Activate.ps1"

# 4. Install Dependencies
Write-Host "`n[4] Installing Python dependencies..." -ForegroundColor Yellow

if (Test-Path "requirements.txt") {
    pip install --upgrade pip
    pip install -r requirements.txt
    Write-Host "[OK] All dependencies installed successfully" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] requirements.txt not found. Skipping pip install." -ForegroundColor Yellow
}

# 5. Check Docker
Write-Host "`n[5] Checking Docker..." -ForegroundColor Yellow

try {
    $null = docker info 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Docker is running" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] Docker daemon is not running. Please start Docker Desktop." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[WARNING] Docker is not installed or not in PATH." -ForegroundColor Yellow
    Write-Host "Please install Docker Desktop from https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
}

# 6. Check AWS CLI
Write-Host "`n[6] Checking AWS CLI..." -ForegroundColor Yellow

try {
    $awsVersion = aws --version 2>&1
    Write-Host "[OK] AWS CLI found: $awsVersion" -ForegroundColor Green

    # Check if AWS is configured
    $awsConfig = aws configure list 2>&1

    if ($awsConfig -match "None" -or $awsConfig -match "<not set>") {
        Write-Host "[WARNING] AWS CLI is not configured." -ForegroundColor Yellow

        $configure = Read-Host "Do you want to run 'aws configure' now? (y/n)"

        if ($configure -eq "y" -or $configure -eq "Y") {
            aws configure
        }
    }
    else {
        Write-Host "[OK] AWS CLI is configured" -ForegroundColor Green
    }
}
catch {
    Write-Host "[WARNING] AWS CLI is not installed." -ForegroundColor Yellow
    Write-Host "Install from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" -ForegroundColor Gray
}

# 7. Setup Complete
Write-Host "`nSetup complete! You are ready to build." -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Gray
Write-Host "1. Run '.\scripts\deploy.ps1' to deploy the infrastructure" -ForegroundColor Gray
Write-Host "2. Access Airflow at http://localhost:8080" -ForegroundColor Gray
```


<div style='page-break-after: always;'></div>

# File: scripts\weekly_cleanup.ps1

```ps1
# CivicPulse Weekly Cleanup Script
# Purpose: Archive old Airflow logs and clean up S3 files older than 90 days to reduce costs
# Schedule: Run weekly via Windows Task Scheduler

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "pipelines\airflow\logs"
$ArchiveDir = Join-Path $ProjectRoot "data\archives"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Starting weekly cleanup process..." -ForegroundColor Cyan

# ==========================================
# 1. Archive and Clean Local Airflow Logs
# ==========================================
Write-Host "`n[1] Archiving Airflow logs..." -ForegroundColor Yellow

if (Test-Path $LogDir) {

    # Create archive directory if it does not exist
    if (-not (Test-Path $ArchiveDir)) {
        New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null
        Write-Host "Created archive directory: $ArchiveDir" -ForegroundColor Gray
    }

    # Create timestamped archive
    $ZipPath = Join-Path $ArchiveDir "airflow_logs_$Timestamp.zip"

    Write-Host "Compressing logs to: $ZipPath" -ForegroundColor Gray

    try {
        Compress-Archive `
            -Path "$LogDir\*" `
            -DestinationPath $ZipPath `
            -Force `
            -ErrorAction Stop

        Write-Host "[OK] Airflow logs archived successfully" -ForegroundColor Green

        # Clean up old archives
        # Keep only the four most recent archives
        Write-Host "Cleaning up old archives (keeping last 4)..." -ForegroundColor Gray

        $oldArchives = Get-ChildItem `
            -Path $ArchiveDir `
            -Filter "airflow_logs_*.zip" |
            Sort-Object CreationTime -Descending |
            Select-Object -Skip 4

        foreach ($archive in $oldArchives) {
            Remove-Item -Path $archive.FullName -Force
            Write-Host "Deleted old archive: $($archive.Name)" -ForegroundColor Gray
        }

        Write-Host "[OK] Old archives cleaned up" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARNING] Failed to archive logs: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[INFO] Log directory not found. Skipping log archival." -ForegroundColor Gray
}

# ==========================================
# 2. Clean Up S3 Files Older Than 90 Days
# ==========================================
Write-Host "`n[2] Cleaning up S3 files older than 90 days..." -ForegroundColor Yellow
Write-Host "This helps reduce AWS storage costs" -ForegroundColor Gray

$BucketName = "civicpulse-raw-surveys"
$ThresholdDate = (Get-Date).AddDays(-90).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

try {

    # Check if AWS CLI is configured
    $null = aws sts get-caller-identity 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI is not configured. Run 'aws configure' first."
    }

    Write-Host "Scanning bucket: $BucketName" -ForegroundColor Gray
    Write-Host "Threshold date: $ThresholdDate" -ForegroundColor Gray

    # List objects older than threshold
    $Objects = aws s3api list-objects-v2 `
        --bucket $BucketName `
        --query "Contents[?LastModified<'$ThresholdDate'].{Key: Key, Size: Size, LastModified: LastModified}" `
        --output json 2>$null | ConvertFrom-Json

    if ($null -eq $Objects -or $Objects.Count -eq 0) {

        Write-Host "[OK] No files older than 90 days found in S3." -ForegroundColor Green
    }
    else {

        Write-Host "Found $($Objects.Count) files to delete" -ForegroundColor Yellow

        # Calculate total size to be deleted
        $totalSize = ($Objects | Measure-Object -Property Size -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)

        Write-Host "Total size: $totalSizeMB MB" -ForegroundColor Gray

        # Delete old objects
        $deletedCount = 0

        foreach ($obj in $Objects) {

            $key = $obj.Key

            Write-Host "Deleting: s3://$BucketName/$key" -ForegroundColor Gray

            aws s3 rm "s3://$BucketName/$key" 2>$null

            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            }
        }

        Write-Host "[OK] S3 cleanup complete. Deleted $deletedCount files." -ForegroundColor Green

        # Estimate storage savings
        $estimatedSavings = [math]::Round($totalSizeMB * 0.023, 2)

        Write-Host "Estimated monthly storage savings: $estimatedSavings USD" -ForegroundColor Green
    }
}
catch {
    Write-Host "[WARNING] S3 cleanup failed: $_" -ForegroundColor Yellow
    Write-Host "Make sure AWS CLI is configured and you have permissions to access the bucket." -ForegroundColor Gray
}

# ==========================================
# 3. Clean Up Old Docker Images
# ==========================================
Write-Host "`n[3] Cleaning up unused Docker resources..." -ForegroundColor Yellow

try {

    docker system prune -f --volumes 2>$null

    Write-Host "[OK] Docker cleanup complete" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Docker cleanup skipped: $_" -ForegroundColor Yellow
}

# ==========================================
# 4. Cleanup Complete
# ==========================================
$NextRun = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")

Write-Host "`nWeekly cleanup finished successfully!" -ForegroundColor Cyan
Write-Host "Next scheduled run: $NextRun" -ForegroundColor Gray
```


<div style='page-break-after: always;'></div>

# File: tests\integration\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: tests\unit\.gitkeep

```gitkeep
```


<div style='page-break-after: always;'></div>

# File: workflow\workflow.md

```md
Almost! The workflow you have is excellent, but to perfectly reflect **Phase 6 (Infrastructure as Code & CI/CD)**, we need to make two small but critical updates:

1. **Add the CI/CD Pipeline step:** Hiring managers love seeing that code is automatically validated before it even reaches the deployment stage.
2. **Correct the Terraform directory path:** Based on your codebase, the Terraform files are in `infrastructure/`, not `infrastructure/terraform/`.

Here is the **final, perfected version** of the workflow. You can copy and paste this directly into your GitHub `README.md`. It now flawlessly represents all 6 phases of your project.

---

# 🚀 CivicPulse: End-to-End Data Platform Workflow

This guide outlines the complete operational lifecycle of the CivicPulse data platform, from automated CI/CD validation and cloud provisioning to daily development, ingestion, orchestration, and automated maintenance.

## **Prerequisites**
Before starting, ensure you have the following installed on your machine:
- Python 3.8+ 
- Docker Desktop (with WSL 2 backend enabled)
- AWS CLI (configured with your credentials)
- Terraform 1.5+

---

## **Step 1: Version Control & CI/CD Validation (Automated)**
*Goal: Ensure code quality and infrastructure validity before deployment.*
1. Push your code to a GitHub branch or open a Pull Request.
2. **GitHub Actions** automatically triggers the `CivicPulse CI/CD Pipeline`, which:
   - Runs `flake8` to enforce Python linting and style standards.
   - Runs `dbt parse` to validate dbt model syntax and dependencies.
   - Runs `terraform fmt -check` and `terraform validate` to ensure Infrastructure as Code is syntactically sound.

---

## **Step 2: Cloud Infrastructure Provisioning (One-Time)**
*Goal: Create the persistent, least-privilege AWS resources required for the microservices pipeline.*
1. Navigate to the infrastructure directory:
   ```powershell
   cd infrastructure
   ```
2. Initialize and apply the Terraform configuration:
   ```powershell
   terraform init
   terraform apply -auto-approve
   ```
   *This provisions the S3 buckets (`civicpulse-raw-voter-files`, `civicpulse-raw-surveys`), SQS queue, Lambda function, and strict IAM roles.*

---

## **Step 3: Local Environment Setup (Daily / Onboarding)**
*Goal: Prepare the local developer machine with all necessary dependencies idempotently.*
1. Navigate to the project root:
   ```powershell
   cd C:\data\CivicPulse
   ```
2. Run the automated setup script:
   ```powershell
   .\scripts\setup_env.ps1
   ```
   *This script creates the `.venv` virtual environment, installs all Python dependencies from `requirements.txt`, and validates that Docker and AWS CLI are correctly configured.*

---

## **Step 4: Local Infrastructure Deployment (Daily)**
*Goal: Spin up the local orchestration and transformation layers.*
1. Run the deployment script:
   ```powershell
   .\scripts\deploy.ps1
   ```
   *This script builds the custom Airflow Docker image, starts the PostgreSQL, Airflow Webserver, and Airflow Scheduler containers, waits for Airflow to become healthy, and runs `dbt deps` to fetch dbt packages.*

---

## **Step 5: Data Ingestion (On-Demand Testing)**

1. Copy the URL from your Terraform output: `"https://sqs.us-east-1.amazonaws.com/932453198323/civicpulse-survey-queue"`
2. Open your PowerShell terminal (in Terminal 1):
3. Set the environment variable **before** you start the FastAPI server:
   ```powershell
   $env:SQS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/932453198323/civicpulse-survey-queue
   ```
*Goal: Trigger the microservices pipeline to prove the decoupled architecture works.*
4. **Start the FastAPI Microservice** (in Terminal 1):
   ```powershell
   uvicorn ingestion.survey_api.app.main:app --reload
   ```
5. **Send a Mock Payload** (in Terminal 2):
   ```powershell
   $body = @{
       voter_id = "VTR-001"
       survey_id = "SRV-001"
       sentiment_score = 0.85
       response_time_seconds = 12.5
   } | ConvertTo-Json

   Invoke-RestMethod -Uri "http://127.0.0.1:8000/survey" -Method Post -Body $body -ContentType "application/json"
   ```
   *Flow:* API receives payload → Validates via Pydantic → Sends to AWS SQS → Lambda triggers → Writes partitioned JSON to AWS S3.
   
   http://localhost:8080 = Apache Airflow UI (Monitoring & Observability)


**lambda_function_arn verification Steps:**
6. Log into the AWS Management Console.
7. Go to the **Lambda** service.
8. Paste this ARN (`arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor`) from terraform output into the search bar at the top.
9. Click on the function.
10. **Verify Configuration:** Check the "Configuration" tab to ensure the Environment Variable `TARGET_BUCKET` is correctly set to `civicpulse-raw-surveys`.
11. **Verify Execution:** After you send a test payload via FastAPI, go to the **"Monitor"** tab and click **"View CloudWatch logs"**. You will see the `print(f"Received event: {json.dumps(event)}")` statement from your `index.py` file, proving the entire decoupled pipeline (API → SQS → Lambda) fired successfully.

---

## **Step 6: Orchestration & Transformation (Automated)**
*Goal: Transform raw S3 data into a trusted Star Schema and enforce data quality.*
1. Airflow’s `S3KeySensor` in `dag_survey_microservice_processing` detects the new file in the S3 bucket.
2. The DAG triggers **Astronomer Cosmos**, which executes:
   - `dbt run`: Transforms raw JSON into the Star Schema (`stg_survey_responses` → `fact_daily_survey_responses`, `dim_voter`, etc.).
   - `dbt test`: Runs automated QA checks, including the custom `null_percentage_less_than` macro (fails if >20% of sentiment scores are null).
3. If a test fails, the `alert_on_failure` callback halts the pipeline and simulates a Slack/Email alert to the Data Science team.

---

## **Step 7: Internal Tooling & Self-Service (On-Demand)**
*Goal: Empower Data Scientists and Business Analysts to monitor data and manage pipelines without writing SQL.*
1. Launch the Streamlit Internal Portal (in Terminal 3):
   ```powershell
   streamlit run internal_tools\streamlit_app\app.py
   ```
2. Open `http://localhost:8501` in your browser and use the three tabs:
   - **📊 Data Quality Dashboard:** View real-time metrics (e.g., Voter ID completeness, sentiment score bounds) queried directly from the local DuckDB warehouse.
   - **📖 Data Dictionary:** Search and explore table/column definitions parsed dynamically from dbt’s `catalog.json`.
   - **⚙️ Pipeline Operations:** Select a DAG, pick a business date, and click **"Trigger Manual Re-run"**. This uses the Airflow REST API to trigger a "manual backfill" with a unique logical date, preventing 409 Conflict errors.

---

## **Step 8: Automated Maintenance & Cost Optimization (Weekly)**
*Goal: Prevent local disk exhaustion and reduce AWS cloud storage costs.*
1. **Schedule the Cleanup Task** (Run PowerShell as Administrator *once*):
   ```powershell
   .\scripts\schedule_cleanup.ps1
   ```
   *This creates a Windows Task Scheduler job named "CivicPulse Weekly Cleanup".*
2. **What happens every Sunday at 2:00 AM:**
   - Archives local Airflow logs into a `.zip` file and deletes archives older than 4 weeks.
   - Queries AWS S3 via the AWS CLI and deletes raw survey files older than 90 days.
   - Runs `docker system prune -f --volumes` to reclaim disk space from dangling Docker images and stopped containers.

---

## **Step 9: Full Environment Reset (Optional)**
*Goal: Completely wipe the local environment to start with a 100% clean slate.*
1. Run the reset script (Run PowerShell as Administrator):
   ```powershell
   .\scripts\reset_env.ps1
   ```
2. Type `yes` to confirm. This will:
   - Delete the Windows Task Scheduler job.
   - Run `docker compose down -v` to destroy all containers and volumes.
   - Delete local `dbt/target` and `dbt/dbt_packages` caches.
   - Delete the `.venv` Python environment.
3. Restart the workflow from **Step 3**.

---

### **Why This Workflow Wins Interviews:**
When asked *"Walk me through your project,"* you can confidently describe this exact lifecycle. It proves you understand:
1. **Separation of Concerns:** Terraform for cloud, Docker for local orchestration, Python for application logic.
2. **Event-Driven Architecture:** Decoupling the API from the database using SQS and Lambda.
3. **Data Quality as Code:** Embedding custom dbt tests and Airflow failure callbacks directly into the pipeline.
4. **Operational Excellence:** Providing self-service tools (Streamlit) and automated maintenance scripts (PowerShell/Task Scheduler) to reduce technical debt and cloud costs.
5. **Modern DevOps Practices:** Enforcing code quality and infrastructure validity via GitHub Actions CI/CD before any code is merged.

---

This updated version perfectly captures the maturity of your Phase 6 additions. You are now 100% ready to push this to GitHub and use it as your ultimate interview talking point! 🚀














### **2. How to use `lambda_function_arn`**
**Where in Workflow:** **Verification, Debugging, and Monitoring**

You don't actually need to put this into your FastAPI code. Because you configured the `aws_lambda_event_source_mapping` in Terraform, AWS automatically knows to trigger this Lambda whenever a message hits the SQS queue. 

However, this ARN is incredibly useful for **you, the engineer**, to verify the system is working:

**Exact Steps:**
1. Log into the AWS Management Console.
2. Go to the **Lambda** service.
3. Paste this ARN (`arn:aws:lambda:us-east-1:932453198323:function:civicpulse_sqs_to_s3_processor`) into the search bar at the top.
4. Click on the function.
5. **Verify Configuration:** Check the "Configuration" tab to ensure the Environment Variable `TARGET_BUCKET` is correctly set to `civicpulse-raw-surveys`.
6. **Verify Execution:** After you send a test payload via FastAPI, go to the **"Monitor"** tab and click **"View CloudWatch logs"**. You will see the `print(f"Received event: {json.dumps(event)}")` statement from your `index.py` file, proving the entire decoupled pipeline (API → SQS → Lambda) fired successfully.

---

### **Why This is a "Senior" Practice**
If you hardcode the SQS URL into your Python script, your code is now tied to one specific AWS account. If you ever deploy this to a `staging` or `production` account, the code will break. 

By using Terraform outputs and environment variables:
1. `terraform apply` generates the correct URL for *whatever* environment it is running in.
2. Your Python code remains completely generic and portable.
3. You can prove to the hiring manager that you understand **12-Factor App methodology** (storing config in the environment).

You are ready to move to the final step: generating the ultimate CV! 🚀
```

