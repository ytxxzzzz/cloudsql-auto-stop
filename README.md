# cloudsql-auto-stop
プロジェクト内で稼働中のcloudsqlを、AM2時に全て停止する。

- GCP内に構築するリソース
  - Cloud scheduler
  - Cloud Functions
  - GCSバケット(Functionへのパッケージデプロイ用)
  - Functionの実行サービスアカウント

## 利用準備
以下のようにpipenvをインストールし、パッケージインストールをする。
```
$ pip install pipenv
$ pipenv sync
```

## インフラ構築
以下のコマンドでGCP上に各種リソースを構築します。
```
$ terraform apply
```
インフラ構築先のプロジェクトIDの入力を促されるので入力します。  
構築先プロジェクトIDの各種リソース作成権限のあるアカウントで実行してください。  
※インフラを構築すると、指定時刻に容赦なく対象プロジェクトのCloudSQL全インスタンスが停止されるので注意してください。

## デバッグ方法
上記利用準備ができていれば、`functions_src/main.py`をVSCode等でデバッグできるはずです。  
※予め、環境変数`GCP_PROJECT`の指定が必要です。
