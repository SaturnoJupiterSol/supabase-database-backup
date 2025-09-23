
\restrict F4McTqg9U7cJ6fmei8khojoTfaUV39PyJc7B0xfHl3gZsUwjmqugDjRLx1NHnml

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict F4McTqg9U7cJ6fmei8khojoTfaUV39PyJc7B0xfHl3gZsUwjmqugDjRLx1NHnml

RESET ALL;
