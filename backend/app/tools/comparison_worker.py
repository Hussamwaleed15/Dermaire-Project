"""Run one isolated comparison job; default adapter is intentionally unavailable.

Usage: python -m app.tools.comparison_worker --plan-id ID
Only use against a deliberately configured isolated database until deployment
review. This entrypoint never enables or configures a live model/provider.
"""
import argparse
import json
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.tools.rehearse_current_schema import validate_target
from app.services.comparison_jobs import run_one


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-id",required=True)
    parser.add_argument("--database-url",required=True)
    args=parser.parse_args()
    target=validate_target(args.database_url,os.environ.get("ENVIRONMENT"))
    engine=create_engine(target)
    with Session(engine) as db:
        from app.services.agent_platform import expire_requests
        expire_requests(db)
        result=run_one(db,args.plan_id)
        # Operational output omits identifiers, evidence, image references/results.
        print(json.dumps({"state":result["state"],"provider":"disabled"}))
    engine.dispose()


if __name__=="__main__":main()
