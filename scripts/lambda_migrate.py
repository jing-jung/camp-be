"""
Lambda를 통해 DB 마이그레이션을 실행하는 스크립트
"""
import json
import subprocess
import sys

def lambda_handler(event, context):
    """Lambda handler for running migrations"""
    try:
        # Run alembic upgrade
        result = subprocess.run(
            ["alembic", "upgrade", "head"],
            capture_output=True,
            text=True,
            check=True
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Migration completed successfully',
                'stdout': result.stdout,
                'stderr': result.stderr
            })
        }
    except subprocess.CalledProcessError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Migration failed',
                'stdout': e.stdout,
                'stderr': e.stderr
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': f'Error: {str(e)}'
            })
        }

if __name__ == '__main__':
    # For local testing
    result = lambda_handler({}, {})
    print(json.dumps(result, indent=2))
