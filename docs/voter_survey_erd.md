# CivicPulse Star Schema ERD

Copy the code block below into [mermaid.live](https://mermaid.live) to generate and download the PDF for your interview portfolio.

```mermaid
erDiagram
    FACT_DAILY_SURVEY_RESPONSES {
        string response_id PK
        string voter_id FK
        string survey_id FK
        string geography_id FK
        date date_id FK
        float sentiment_score
        float response_time_seconds
    }

    DIM_VOTER {
        string voter_id PK
        string first_name
        string last_name
        string registration_status
        string party_affiliation
        string geography_id FK
    }

    DIM_GEOGRAPHY {
        string geography_id PK
        string district_name
        string precinct_name
        string demographic_type
    }

    DIM_SURVEY_METADATA {
        string survey_id PK
        string question_text
        string pollster_name
        date survey_date
    }

    DIM_DATE {
        date date_id PK
        int year
        int month
        int day
        string day_type
    }

    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_VOTER : "has"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_SURVEY_METADATA : "answers"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_GEOGRAPHY : "located_in"
    FACT_DAILY_SURVEY_RESPONSES ||--|| DIM_DATE : "occurred_on"
    DIM_VOTER }o--|| DIM_GEOGRAPHY : "resides_in"