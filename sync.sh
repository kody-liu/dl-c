# Sync from S3 to local (use --dryrun to preview; --delete removes local files not present in S3)
AWS_PROFILE=my-profile aws s3 sync s3://lie-cheater ./local_dir --region ap-northeast-1 --delete