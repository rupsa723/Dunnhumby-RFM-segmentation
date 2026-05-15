# 🛒 RFM Customer Segmentation
### Dunnhumby — The Complete Journey | Python · Power BI

> *"The retailer treats all 2,500 households the same. Who's worth keeping? Who's already gone? And are we wasting money on customers who'd buy anyway?"*

---

## The Short Version

A retail grocery chain had 2 years of transaction data and zero customer intelligence. I built an end-to-end RFM segmentation pipeline that answers three business questions most retailers never ask properly.

**The uncomfortable findings:**

- 🏆 **Champions are 20.4% of customers but drive 45.4% of revenue** — and the business has no idea who they are
- ⚠️ **42.6% of households show churn signals** — At Risk and Lost segments combined
- 💸 **916 households have never received a single campaign** — including Lost customers at 95.5% targeting yet 5.4% redemption
- 🎟️ **Champions absorb 60% of coupon value** despite buying without incentives

---

## Dashboard Preview

![Dashboard Preview](assets/dashboard_preview.png)
*Page 1 — Executive Summary. Add your screenshot as `assets/dashboard_preview.png` in the repo.*

📊 **[Download Interactive Dashboard (.pbix)](https://drive.google.com/file/d/1FVWRXMAGhvVRbKGhjglqDA0D-tWK2nkj/view?usp=sharing)**  
*Requires Power BI Desktop — free download from Microsoft*

📄 **Dashboard PDF** also available in this repo — shows all pages with key segment selections, no software required.

---



| Tool | Purpose |
|------|---------|
| Python (pandas, numpy) | RFM engine, data cleaning, quintile scoring |
| Matplotlib | EDA visualisations |
| Power BI (DAX) | Interactive dashboard, business metrics |
| Dataset | [Dunnhumby — The Complete Journey](https://www.kaggle.com/datasets/frtgnn/dunnhumby-the-complete-journey) |

---

## What I Built

```
2,595,732 transactions → cleaned → RFM scored → 8 segments → Power BI dashboard
```

**The RFM Engine (Python)**  
Recency, Frequency, and Monetary scores per household using `pd.qcut()` quintile binning — not arbitrary cutoffs. All three distributions are heavily right-skewed, so equal-width bins would have pushed 90% of customers into Score 1. Quintile binning forces genuine differentiation.

**8 Customer Segments**

| Segment | Count | Avg RFM Score | Revenue % |
|---------|-------|--------------|-----------|
| Champions | 509 | 13.84 | 45.4% |
| Loyal | 330 | 11.53 | 17.0% |
| At Risk | 565 | 8.36 | 18.4% |
| Potential Loyalists | 306 | 9.81 | 8.5% |
| Lost | 500 | 4.73 | 8.1% |
| One-time Buyers | 198 | 5.07 | 1.9% |
| Low Value | 62 | 5.45 | 0.4% |
| New Customers | 30 | 7.33 | 0.2% |

**The Power BI Dashboard (4 pages)**
- Page 0 — Methodology: how the scoring works
- Page 1 — Executive Summary: the business picture
- Page 2 — Segment Deep-Dive: demographics + product behaviour per segment
- Page 3 — Promotion Intelligence: campaign and coupon analysis

---

## Key Insight That Surprised Me

Champions spend **$29.22 per trip** — *less* than One-time Buyers at $36.56.  
But Champions made **246 trips** over two years. One-time Buyers made 1.  
**Frequency is the superpower, not basket size.** Most retailers optimise for basket size. Wrong metric.

---

## The Wasted Spend Problem

| Segment | Targeting Rate | Coupon Redemption |
|---------|---------------|------------------|
| Champions | 99.1% | 42.8% |
| Loyal | 95.9% | 27.9% |
| At Risk | 86.7% | 11.0% |
| Lost | 95.5% | 5.4% |
| Low Value | 0.0% | 0.0% |

Champions are being sent campaigns they don't need. A Champion visits every 2.1 days on average — they shop continuously regardless of whether they received a campaign. The 97.9% "response rate" is measuring shopping frequency, not campaign effectiveness.

**Campaign type breakdown reveals a deeper problem:**

| Campaign Type | Share of All Campaigns | Household Coverage |
|---------------|----------------------|-------------------|
| TypeB | 63.3% | 40.9% — lowest coverage |
| TypeC | 20.0% | 15.9% — near invisible |
| TypeA | 16.7% | 60.5% — most evenly distributed |

The most common campaign type (TypeB) reaches the fewest households. TypeC — run 6 times over 2 years — reached only 397 of 2,500 households (15.9%). Neither type meaningfully changes coupon redemption behaviour outside Champion and Loyal segments. The campaign mix is heavily concentrated on already-loyal customers regardless of type.

---

## Recommendations

1. **Reduce Champion campaign spend by 30-40%** — replace with loyalty recognition. They buy without incentives.
2. **Urgently close the At Risk targeting gap** — 565 households, 18.4% revenue, 13.25% never reached. Highest recovery ROI.
3. **Redesign coupon strategy** — redirect from Champions (who redeem but don't need it) to Potential Loyalists (who need the habit nudge).
4. **Expand TypeC and TypeA campaign reach** — TypeB dominates at 63% but has the worst household coverage at 40.9%.

---

## Data Limitations (Being Honest)

- Demographic coverage: only 801 of 2,500 households have demographic data (32%)
- Day numbers assumed to start Jan 1 2017 — standard assumption for this dataset
- No campaign control group — response rates cannot be interpreted as causal lift
- Static RFM: scores reflect full 2-year window, not recent trajectory

---

## Project Files

| File | Description |
|------|-------------|
| `RFM_Engine.ipynb` | End-to-end Python pipeline — data loading, EDA, RFM scoring, segmentation, campaign and coupon analysis with verified outputs at each stage |
| `rfm_segments.csv` | Clean output from Python — 2,500 households with RFM scores, segment labels and demographic columns, ready to load into Power BI |
| `RFM_Customer_Segmentation.pptx` | 11-slide project presentation covering methodology, 4 key findings, data limitations and recommendations |
| `RFM_Customer_Segmentation.pdf` | Static PDF of all 4 dashboard pages with key segment selections — no software required to view |
| `RFM_Customer_Segmentation.pbix` | Full interactive Power BI dashboard — [download from Google Drive](https://drive.google.com/file/d/1FVWRXMAGhvVRbKGhjglqDA0D-tWK2nkj/view?usp=sharing) (26MB, requires Power BI Desktop) |

> Dataset not included — download from [Kaggle](https://www.kaggle.com/datasets/frtgnn/dunnhumby-the-complete-journey) (free account required).

---

*Built with Python and Power BI. Dataset: Dunnhumby The Complete Journey (Kaggle).*
