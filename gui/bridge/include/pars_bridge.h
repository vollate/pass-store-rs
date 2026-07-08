// Native JSON ABI used by mobile autofill provider processes.
char *pars_autofill_query_candidates_json(const char *request_json);
char *pars_autofill_resolve_credential_json(const char *request_json);
void pars_autofill_free_string(char *value);
