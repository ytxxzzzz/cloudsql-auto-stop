terraform {
  required_version = "~> 1.4.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.57.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.57.0"
    }
  }

  backend "gcs" {
    bucket = "cloudsql-auto-stop-tfstate"
    prefix = "terraform/state"
  }
}

variable "project" {
  type        = string
  description = "CloudSQLインスタンスの自動停止をしたいGCPプロジェクトIDを指定します。各種リソースはこのプロジェクトに構築されます。"
}

locals {
  regions = {
    tokyo = "asia-northeast1"
    us    = "us-central1"
  }

  zones = {
    tokyo-a = "${local.regions.tokyo}-a"
    tokyo-b = "${local.regions.tokyo}-b"
    tokyo-c = "${local.regions.tokyo}-c"

    us-central-a = "${local.regions.us}-a"
    us-central-b = "${local.regions.us}-b"
    us-central-c = "${local.regions.us}-c"
    us-central-f = "${local.regions.us}-f"
  }
}

# requirements.txtをpipenvから抽出し出力する
resource "null_resource" "make_requirements" {
  triggers = {
    script_hash  = "${sha256("functions_src/cloudsql_auto_stop.py")}"
    pipfile_hash = "${sha256("./Pipfile.lock")}"
  }

  provisioner "local-exec" {
    working_dir = "."
    command     = "pipenv requirements > functions_src/requirements.txt"
  }
}

# Cloud Functionsにアップロードするファイルをzipに固める。
data "archive_file" "function_archive" {
  type        = "zip"
  source_dir  = "./functions_src"
  output_path = "./functions_src.zip"
  depends_on = [
    null_resource.make_requirements
  ]
}

# 作成したパッケージをデプロイするためのGCSバケット
resource "google_storage_bucket" "functions_bucket" {
  project       = var.project
  name          = "cloudsql-auto-stop-deploy"
  location      = local.regions.us
  storage_class = "STANDARD"
}

# zipファイルをアップロードする
resource "google_storage_bucket_object" "packages" {
  name   = "packages/functions.${data.archive_file.function_archive.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.function_archive.output_path
}

# CloudFunctionsのデプロイ
resource "google_cloudfunctions_function" "stop_cloudsql_instances" {
  project                      = var.project
  region                       = local.regions.us
  name                         = "stop-cloudsql-instances"
  runtime                      = "python310"
  source_archive_bucket        = google_storage_bucket.functions_bucket.name
  source_archive_object        = google_storage_bucket_object.packages.name
  entry_point                  = "stop_cloudsql_instances"
  timeout                      = 120
  trigger_http                 = true
  https_trigger_security_level = "SECURE_ALWAYS"

  available_memory_mb = 256

  # 環境変数にGCLOUD_PROJECTを設定
  environment_variables = {
    GCP_PROJECT = var.project
  }

  # 依存関係のあるファイルを指定
  # main.pyとrequirements.txtが必要
  depends_on = [
    google_storage_bucket_object.packages
  ]
}

resource "google_service_account" "func-invoker" {
  project      = var.project
  account_id   = "stop-cloudsql-invoker"
  display_name = "Cloud Function ${google_cloudfunctions_function.stop_cloudsql_instances.name} Invoker Service Account"
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.stop_cloudsql_instances.project
  region         = google_cloudfunctions_function.stop_cloudsql_instances.region
  cloud_function = google_cloudfunctions_function.stop_cloudsql_instances.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.func-invoker.email}"
}

# CloudSchedulerのターゲットとなるHTTPエンドポイントの作成
resource "google_cloud_scheduler_job" "stop_cloudsql_instances" {
  project     = var.project
  region      = local.regions.us
  name        = "stop-cloudsql-instances"
  description = "Stop all running Cloud SQL instances"
  schedule    = "0 2 * * *"
  time_zone   = "Asia/Tokyo"

  http_target {
    uri         = google_cloudfunctions_function.stop_cloudsql_instances.https_trigger_url
    http_method = "GET"
    oidc_token {
      service_account_email = google_service_account.func-invoker.email
    }
  }
}
