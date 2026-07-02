# Runpodのファイルダウンロードを自動化します
# JupyterLabで実行
# cd /workspace/リポジトリ名
nohup python download_all.py --config models.json --workers 3 > download.log 2>&1 &

# 進捗確認
tail -f download.log
