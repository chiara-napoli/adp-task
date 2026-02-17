"""S3-based number adder script.

This script downloads a file of numbers from an S3 input prefix,
computes their sum, and uploads the result to an S3 output prefix.

Environment Variables:
    BUCKET_NAME: Name of the S3 bucket to operate on.
    INPUT_PREFIX: S3 key prefix for input files.
    OUTPUT_PREFIX: S3 key prefix for output files.
    AWS_PROFILE (optional): Name of the AWS CLI profile to use.
        If not set, boto3 uses the default credential chain.
"""

import logging
import os
import sys
import tempfile
from typing import Optional
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

def _validate_s3_key(key: str) -> None:
    """Validate that an S3 key does not contain path traversal sequences.
    Args:
        key: The S3 object key to validate.
    Raises:
        ValueError: If the key contains '..' path traversal sequences.
    """
    if ".." in key:
        raise ValueError(
            f"Invalid S3 key '{key}': path traversal sequences ('..') are not allowed."
        )

class S3BucketManager:
    """Manages reading and writing files to an S3 bucket.
    This class provides methods to download files from an input prefix
    and upload files to an output prefix within a single S3 bucket.
    Attributes:
        s3: The boto3 S3 client instance.
        bucket: The name of the S3 bucket.
        input_prefix: The S3 key prefix used for reading input files.
        output_prefix: The S3 key prefix used for writing output files.
    """

    def __init__(
        self,
        bucket_name: str,
        input_prefix: str,
        output_prefix: str,
        profile_name: Optional[str] = None,
    ) -> None:
        """Initialize the S3BucketManager.
        Args:
            bucket_name: The name of the S3 bucket.
            input_prefix: The S3 key prefix for input files.
            output_prefix: The S3 key prefix for output files.
            profile_name: Optional AWS CLI profile name. If provided,
                a boto3 session is created with this profile. Otherwise,
                the default credential chain is used.
        """
        if profile_name:
            session = boto3.Session(profile_name=profile_name)
            self.s3 = session.client("s3")
        else:
            self.s3 = boto3.client("s3")
        self.bucket = bucket_name
        self.input_prefix = input_prefix
        self.output_prefix = output_prefix

    def write_data_to_output(self, local_file_path: str, s3_key: str) -> None:
        """Upload a local file to the output prefix in S3.
        Constructs the full S3 destination key by prepending the configured
        output prefix to the provided ``s3_key``, then uploads the file.
        Args:
            local_file_path: Absolute path to the local file to upload.
            s3_key: The relative S3 object key (appended to output_prefix).
        Raises:
            ValueError: If ``s3_key`` contains path traversal sequences.
            FileNotFoundError: If ``local_file_path`` does not exist.
            NoCredentialsError: If AWS credentials are not available.
        """
        _validate_s3_key(s3_key)
        try:
            destination = f"{self.output_prefix}{s3_key}"
            self.s3.upload_file(local_file_path, self.bucket, destination)
            logger.info("Uploaded %s to s3://%s/%s", local_file_path, self.bucket, destination)
        except FileNotFoundError:
            logger.error("The file was not found: %s", local_file_path)
            raise
        except NoCredentialsError:
            logger.error("AWS credentials not available")
            raise

    def read_data_from_input(self, s3_key: str, local_path: str) -> None:
        """Download a file from the input prefix in S3 to a local path.
        Constructs the full S3 source key by prepending the configured
        input prefix to the provided ``s3_key``, then downloads the file.
        Args:
            s3_key: The relative S3 object key (appended to input_prefix).
            local_path: Absolute path where the downloaded file will be saved.
        Raises:
            ValueError: If ``s3_key`` contains path traversal sequences.
            ClientError: If the S3 download fails (e.g., object not found,
                permission denied).
            NoCredentialsError: If AWS credentials are not available.
        """
        _validate_s3_key(s3_key)
        try:
            source = f"{self.input_prefix}{s3_key}"
            self.s3.download_file(self.bucket, source, local_path)
            logger.info("Downloaded s3://%s/%s to %s", self.bucket, source, local_path)
        except ClientError as e:
            logger.error("Error downloading s3://%s/%s: %s", self.bucket, s3_key, e)
            raise
        except NoCredentialsError:
            logger.error("AWS credentials not available")
            raise


class Adder:
    """Reads numbers from a file, computes their sum, and writes the result.
    Lines that cannot be parsed as numbers are skipped with a warning.
    Attributes:
        input_file_path: Path to the file containing numbers (one per line).
        output_file_path: Path to the file where the sum will be written.
    """

    def __init__(self, input_file_path: str, output_file_path: str) -> None:
        """Initialize the Adder.
        Args:
            input_file_path: Path to the input file with one number per line.
            output_file_path: Path to the file where the result will be written.
        """
        self.input_file_path = input_file_path
        self.output_file_path = output_file_path

    def add(self) -> float:
        """Read numbers from the input file, sum them, and write to the output file.
        Each line of the input file is expected to contain a single number.
        Blank lines are skipped. Lines that cannot be parsed as a float
        are logged as warnings and skipped.
        Returns:
            The computed sum of all valid numbers in the input file.
        """
        total = 0.0
        with open(self.input_file_path, "r") as f_in:
            for line_number, line in enumerate(f_in, start=1):
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    total += float(stripped)
                except ValueError:
                    logger.warning(
                        "Line %d is not a valid number: '%s' — skipping",
                        line_number,
                        stripped,
                    )
        with open(self.output_file_path, "w") as f_out:
            f_out.write(str(total))
        logger.info("Sum written to %s: %s", self.output_file_path, total)
        return total

if __name__ == "__main__":
    bucket_name = os.getenv("BUCKET_NAME")
    input_prefix = os.getenv("INPUT_PREFIX")
    output_prefix = os.getenv("OUTPUT_PREFIX")
    aws_profile = os.getenv("AWS_PROFILE")  # optional

    missing = [
        name
        for name, val in [
            ("BUCKET_NAME", bucket_name),
            ("INPUT_PREFIX", input_prefix),
            ("OUTPUT_PREFIX", output_prefix),
        ]
        if not val
    ]
    if missing:
        logger.error(
            "Missing required environment variables: %s", ", ".join(missing)
        )
        sys.exit(1)

    manager = S3BucketManager(bucket_name, input_prefix, output_prefix, profile_name=aws_profile)

    with tempfile.TemporaryDirectory() as tmp_dir_name:
        logger.info("Created temporary directory %s", tmp_dir_name)
        # Read the input file, containing the addends, from S3
        input_tmp_file_path = os.path.join(tmp_dir_name, "addends.txt")
        manager.read_data_from_input("addends.txt", input_tmp_file_path)
        # Compute the sum of the addends
        output_tmp_file_path = os.path.join(tmp_dir_name, "sum.txt")
        adder = Adder(input_tmp_file_path, output_tmp_file_path)
        adder.add()
        # Write the output file, containing the sum, to S3
        manager.write_data_to_output(output_tmp_file_path, "sum.txt")
    # The temporary directory is automatically cleaned up when the 'with' block exits.