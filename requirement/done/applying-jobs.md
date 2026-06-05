Greenhouse is a little tricky because there are **two different APIs**:

1. **Job Board API** (public)

   * Used by the crawler.
   * Lets you fetch jobs.
   * Does **not** let you submit applications.

2. **Application API** (per-job application endpoint)

   * Used to actually apply.
   * Requires submitting to a specific job's application URL.
   * Usually includes resume upload, candidate info, answers to questions, EEOC forms, etc.

From the crawler output, you'll typically have:

```json
{
  "external_job_id": "1234567",
  "source_url": "https://job-boards.greenhouse.io/acme/jobs/1234567"
}
```

The safest approach is:

1. Fetch the job details.
2. Discover the application fields.
3. Submit the application.

---

## Step 1: Fetch job details

```go
package greenhouse

import (
	"encoding/json"
	"fmt"
	"net/http"
)

type JobDetail struct {
	ID     int64  `json:"id"`
	Title  string `json:"title"`
	Content string `json:"content"`
}

func GetJob(boardToken string, jobID string) (*JobDetail, error) {
	url := fmt.Sprintf(
		"https://boards-api.greenhouse.io/v1/boards/%s/jobs/%s",
		boardToken,
		jobID,
	)

	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var job JobDetail

	if err := json.NewDecoder(resp.Body).Decode(&job); err != nil {
		return nil, err
	}

	return &job, nil
}
```

Example:

```go
job, err := GetJob("stripe", "1234567")
```

---

## Step 2: Discover application fields

Greenhouse exposes the application form:

```http
GET https://boards-api.greenhouse.io/v1/boards/{board}/jobs/{job_id}
```

Request:

```http
GET https://boards-api.greenhouse.io/v1/boards/stripe/jobs/1234567?questions=true
```

Response contains:

```json
{
  "questions": [
    {
      "label": "First Name",
      "required": true
    },
    {
      "label": "Last Name",
      "required": true
    },
    {
      "label": "Resume",
      "required": true
    }
  ]
}
```

Your agent should parse these dynamically because every company customizes the form.

---

## Step 3: Submit application

The endpoint is typically:

```http
POST
https://boards-api.greenhouse.io/v1/boards/{board}/jobs/{job_id}
```

Example payload:

```json
{
  "first_name": "John",
  "last_name": "Doe",
  "email": "john@example.com",
  "phone": "+15551234567"
}
```

In Go:

```go
type ApplyRequest struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email"`
	Phone     string `json:"phone"`
}
```

```go
func Apply(
	boardToken string,
	jobID string,
	req ApplyRequest,
) error {

	url := fmt.Sprintf(
		"https://boards-api.greenhouse.io/v1/boards/%s/jobs/%s",
		boardToken,
		jobID,
	)

	body, err := json.Marshal(req)
	if err != nil {
		return err
	}

	resp, err := http.Post(
		url,
		"application/json",
		bytes.NewBuffer(body),
	)

	if err != nil {
		return err
	}

	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf(
			"application failed status=%d",
			resp.StatusCode,
		)
	}

	return nil
}
```

---

## Resume Upload

Most Greenhouse applications require:

```txt
resume
cover letter
linkedin
github
portfolio
custom questions
```

Resume upload is usually sent as multipart form data.

Example:

```go
func AddResume(
	writer *multipart.Writer,
	resumePath string,
) error {

	file, err := os.Open(resumePath)
	if err != nil {
		return err
	}

	defer file.Close()

	part, err := writer.CreateFormFile(
		"resume",
		file.Name(),
	)

	if err != nil {
		return err
	}

	_, err = io.Copy(part, file)
	return err
}
```

---

## What I would build for Ceerat

Instead of applying directly from crawler data:

```txt
Crawler
   ↓
Universal Job
   ↓
Application Discovery Service
   ↓
Fetch Greenhouse Form
   ↓
Map Candidate Profile
   ↓
Submit Application
```

Because Greenhouse, Lever, Ashby, Workday, and SmartRecruiters all have different application schemas, you'll eventually want a **UniversalApplication model** that gets translated into provider-specific payloads. That avoids hardcoding application logic per ATS.


Use buider agent for security, architecture and consitency.s