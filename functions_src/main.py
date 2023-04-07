import googleapiclient.discovery
from googleapiclient.discovery import HttpError
import os

sqladmin = googleapiclient.discovery.build("sqladmin", "v1beta4")
project = os.getenv("GCP_PROJECT")


def stop_cloudsql_instances(request):
    instances = sqladmin.instances().list(project=project).execute()
    if "items" not in instances:
        return

    for instance in instances["items"]:
        name = instance["name"]
        # 起動中のものは"ALWAYS"になる
        # https://cloud.google.com/php/docs/reference/cloud-sql-admin/latest/V1beta4.Settings.SqlActivationPolicy
        if instance["settings"]["activationPolicy"] == "ALWAYS":
            # アクティベーションポリシーを"NEVER"にすることで、インスタンス停止できる
            activation_policy = "NEVER"
            data = {"settings": {"activationPolicy": activation_policy}}
            try:
                sqladmin.instances().patch(
                    project=project, instance=name, body=data
                ).execute()
            except HttpError:
                # 処理対象のインスタンスがレプリカの場合や現在メンテナンス作業中の場合NEBERに変更できない。その時には400でエラーとなるので、無視する
                print(
                    f"{name}：レプリカDBか現在メンテナンス中であるため停止できませんでした。"
                    "レプリカの場合は停止状態にできず課金状態が続くので不要になったらすぐに削除することをおススメします。"
                )
                continue
            print(f"{name}：停止しました。")
        else:
            print(f"{name}：既に停止しています。")
    return "正常終了"


if __name__ == "__main__":
    stop_cloudsql_instances(None)
